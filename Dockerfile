FROM intersystemsdc/irishealth-community:preview as builder

RUN \
	--mount=type=bind,src=.,dst=/irisdev/app \
	--mount=type=bind,src=./iris.script,dst=/tmp/iris.script \
	iris start IRIS && \
	iris session IRIS < /tmp/iris.script && \
	iris stop iris quietly

FROM intersystemsdc/irishealth-community:preview as final

ADD --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} https://github.com/grongierisc/iris-docker-multi-stage-script/releases/latest/download/copy-data.py /irisdev/app/copy-data.py

RUN --mount=type=bind,source=/,target=/builder/root,from=builder \
    cp -f /builder/root/usr/irissys/iris.cpf /usr/irissys/iris.cpf && \
    python3 /irisdev/app/copy-data.py -c /usr/irissys/iris.cpf -d /builder/root/ 

# Python stuff
ENV IRISUSERNAME "SuperUser"
ENV IRISPASSWORD "SYS"
ENV IRISNAMESPACE "FHIRSERVER"
ENV IRISINSTALLDIR $ISC_PACKAGE_INSTALLDIR
ENV LD_LIBRARY_PATH=$IRISINSTALLDIR/bin:$LD_LIBRARY_PATH