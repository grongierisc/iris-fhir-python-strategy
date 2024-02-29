FROM intersystemsdc/irishealth-community:preview as builder

RUN \
	--mount=type=bind,src=.,dst=/irisdev/app \
	--mount=type=bind,src=./iris.script,dst=/tmp/iris.script \
	pip3 install -r /irisdev/app/requirements.txt && \
	iris start IRIS && \
	iris session IRIS < /tmp/iris.script && \
	iris stop iris quietly

FROM intersystemsdc/irishealth-community:preview as final

ADD --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} https://github.com/grongierisc/iris-docker-multi-stage-script/releases/latest/download/copy-data.py /irisdev/app/copy-data.py

# copy the python requirements file
COPY --chown=${ISC_PACKAGE_MGRUSER}:${ISC_PACKAGE_IRISGROUP} ./requirements.txt /irisdev/app/requirements.txt

# install the python requirements
RUN pip3 install -r /irisdev/app/requirements.txt

RUN --mount=type=bind,source=/,target=/builder/root,from=builder \
    cp -f /builder/root/usr/irissys/iris.cpf /usr/irissys/iris.cpf && \
    python3 /irisdev/app/copy-data.py -c /usr/irissys/iris.cpf -d /builder/root/ 

# Python stuff
ENV IRISUSERNAME "SuperUser"
ENV IRISPASSWORD "SYS"
ENV IRISNAMESPACE "FHIRSERVER"
ENV IRISINSTALLDIR $ISC_PACKAGE_INSTALLDIR
ENV LD_LIBRARY_PATH=$IRISINSTALLDIR/bin:$LD_LIBRARY_PATH