.PHONY: clean dirs dev images gwvolman_src wholetale_src dms_src home_src dashboard_src sources \
	rebuild_dashboard restart_worker restart_girder globus_handler_src

SUBDIRS = ps homes src
TAG = latest

images:
	docker pull traefik:alpine
	docker pull mongo:3.2
	docker pull redis:latest
	docker pull registry:2.6
	docker pull risingstack/alpine:3.7-v8.10.0-4.8.0
	docker pull wholetale/girder:$(TAG)
	docker pull wholetale/gwvolman:$(TAG)

src/gwvolman:
	git clone https://github.com/whole-tale/gwvolman src/gwvolman

src/wholetale:
	git clone https://github.com/whole-tale/girder_wholetale src/wholetale

src/wt_data_manager:
	git clone https://github.com/whole-tale/girder_wt_data_manager src/wt_data_manager

src/wt_home_dir:
	git clone https://github.com/whole-tale/wt_home_dirs src/wt_home_dir

src/dashboard:
	git clone https://github.com/whole-tale/dashboard src/dashboard
	docker run --rm -ti -v $${PWD}/src/dashboard:/usr/src/node-app risingstack/alpine:3.7-v8.10.0-4.8.0 sh -c "$$(cat dashboard_local/initial_build.sh)"

src/globus_handler:
	git clone https://github.com/whole-tale/globus_handler src/globus_handler

sources: src/gwvolman src/wholetale src/wt_data_manager src/wt_home_dir src/dashboard src/globus_handler

dirs: $(SUBDIRS)

$(SUBDIRS):
	@mkdir $@

services: dirs sources

dev: services
	docker stack deploy --compose-file=docker-stack.yml wt
	./run_worker.sh
	cid=$$(docker ps --filter=name=wt_girder -q);
	while [ -z $${cid} ] ; do \
		  echo $${cid} ; \
		  sleep 1 ; \
	    cid=$$(docker ps --filter=name=wt_girder -q) ; \
	done; \
	true
	docker exec --user=root -ti $$(docker ps --filter=name=wt_girder -q) pip install -e /gwvolman
	docker exec -ti $$(docker ps --filter=name=wt_girder -q) girder-install web --dev --plugins=oauth,gravatar,jobs,worker,wt_data_manager,wholetale,wt_home_dir,globus_handler
	./setup_girder.py

restart_girder: dev
	which jq || echo "Please install jq to execute the 'restart_girder' make target" && exit 1
	docker exec -ti $$(docker ps --filter=name=wt_girder -q) \
		curl -XPUT -s 'http://localhost:8080/api/v1/system/restart' \
			--header 'Content-Type: application/json' \
			--header 'Accept: application/json' \
			--header 'Content-Length: 0' \
			--header "Girder-Token: $$(docker exec -ti $$(docker ps --filter=name=wt_girder -q) \
				curl 'http://localhost:8080/api/v1/user/authentication' \
				--basic --user admin:arglebargle123 \
					| jq -r .authToken.token)"
	
rebuild_dashboard: src/dashboard
	docker run --rm -ti -v $${PWD}/src/dashboard:/usr/src/node-app risingstack/alpine:3.7-v8.10.0-4.8.0 npm install
	docker run --rm -ti -v $${PWD}/src/dashboard:/usr/src/node-app risingstack/alpine:3.7-v8.10.0-4.8.0 ./node_modules/.bin/ember build --environment=production

restart_worker:
	./stop_worker.sh && ./run_worker.sh

clean:
	-./stop_worker.sh
	-./destroy_instances.py
	-docker stack rm wt
	limit=15 ; \
	until [ -z "$$(docker service ls --filter label=com.docker.stack.namespace=wt -q)" ] || [ "$${limit}" -lt 0 ]; do \
	  sleep 2 ; \
	  limit="$$((limit-1))" ; \
	done; true
	limit=15 ; \
	until [ -z "$$(docker network ls --filter label=com.docker.stack.namespace=wt -q)" ] || [ "$${limit}" -lt 0 ]; do \
	  sleep 2 ; \
	  limit="$$((limit-1))" ; \
	done; true
	-docker volume rm wt_mongo-cfg wt_mongo-data
