NAME:=ffp-pdmsrv
VOLUMES:=-v ${CURDIR}/certs/:/etc/openvpn/certs
PORTS:=-p 8942:8942/udp -p 1195:1195/udp -p 1701:1701/udp
CONFIG:=config.env
RESTART:=unless-stopped

CID=`docker ps | grep ${NAME} | cut -d' ' -f1`


build:
	docker build -t ${NAME} .
.PHONY: build

config:
	test -s ${CONFIG} || ( echo -e "\nconfig.env does not exist or is empty. Exiting...\n" ; exit 1 )
.PHONY: config

run: stop remove build config
	docker run -d --privileged --restart ${RESTART} --name ${NAME} --env-file=${CONFIG} -e "GIT_COMMIT=`git rev-parse HEAD`" -e "HOSTHOSTNAME=`hostname`" ${VOLUMES} ${PORTS} ${RUNARGS} ${NAME}
.PHONY: run

shell: running
	docker exec -it "${CID}" bash
.PHONY: shell

stop:
	-docker stop "${CID}"
.PHONY: stop

remove:
	-docker container rm "${NAME}"
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
