NAME:=ffp-pdmsrv
VOLUMES:=
PORTS:=-p 8942:8942/udp
CONFIG:=config.env

CID=`docker ps | grep ${NAME} | cut -d' ' -f1`


build:
	docker build -t ${NAME} .
.PHONY: build

config:
	test -s ${CONFIG} || ( echo -e "\nconfig.env does not exist or is empty. Exiting...\n" ; exit 1 )
.PHONY: config

run: stop build config
	docker run -d --privileged --env-file=${CONFIG}	${VOLUMES} ${PORTS} ${RUNARGS} ${NAME}
.PHONY: run

shell: running
	docker exec -it "${CID}" bash
.PHONY: shell

stop:
	-docker stop "${CID}"
.PHONY: stop

log: running
	docker attach --sig-proxy=false "${CID}"
.PHONY: log

runlog: run log
.PHONY: runlog

running:
	test "${CID}" != "" || ( echo -e "Docker container is not running." ; exit 1 )
.PHONY: running

clean: stop
.PHONY: clean
