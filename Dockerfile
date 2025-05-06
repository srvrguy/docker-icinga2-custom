# This extends the base Icinga2 container image to include custom libraries for
# other check plugins that are added in later in a volume.

# Pull our base image in. This instance of the image will be the target to which
# we apply our modifications
FROM icinga/icinga2:2.14.5 AS icinga2-target

# The base image switches to the icinga user, we need to switch to root to do
# our additions.
USER root

# Additional packages installed via apt.
# Keep package names in alphabetical order
RUN apt-get update ;\
	apt-get install --no-install-recommends --no-install-suggests -y \
		libaio1 libdbi-perl libconfig-general-perl libio-socket-multicast-perl \
		libjson-perl libwww-perl libmodule-find-perl libmonitoring-plugin-perl \
		libsys-sigaction-perl liburi-perl libxml-simple-perl libwww-perl \
		python3-bson python3-dnspython python3-pymongo python3-pytest unzip ;\
	apt-get clean ;\
	rm -vrf /var/lib/apt/lists/*

# download and set up the Oracle Instant Client basic package
RUN	ORACLEARCH=$([ $(dpkg --print-architecture) = "amd64" ] && echo "x64" || echo $(dpkg --print-architecture) ) ;\
	curl -O https://download.oracle.com/otn_software/linux/instantclient/1925000/instantclient-basiclite-linux.$ORACLEARCH-19.25.0.0.0dbru.zip ;\
	mkdir -p /opt/oracle ;\
	unzip -n 'instantclient*.zip' -d /opt/oracle ;\
	cd /opt/oracle ;\
	ln -s instantclient_19_25 instantclient ;\
	echo "/opt/oracle/instantclient" > /etc/ld.so.conf.d/oracleinstantclient.conf ;\
	/sbin/ldconfig

###########################
### BEGIN Custom Stages ###
###########################
# Things we can't do cleanly in our target happen now.

# Custom Check Plugins that need to be bundled
FROM buildpack-deps:scm as clone-plugins

RUN git clone --bare https://github.com/lausser/check_oracle_health.git ;\
	git -C check_oracle_health.git archive --prefix=check_oracle_health/ 4bf20a38be3d4934c00da6845cf29ab648e09e65 |tar -x ;\
	rm -rf *.git

FROM debian:bookworm-slim as build-plugins

RUN apt-get update ;\
	apt-get upgrade -y;\
	apt-get install --no-install-recommends --no-install-suggests -y \
		autoconf automake make ;\
	apt-get clean ;\
	rm -vrf /var/lib/apt/lists/*

COPY --from=clone-plugins /check_oracle_health /check_oracle_health

RUN cd /check_oracle_health ;\
	mkdir bin ;\
	autoreconf ;\
	./configure "--build=$(uname -m)-unknown-linux-gnu" --libexecdir=/usr/lib/nagios/plugins ;\
	make ;\
	make install "DESTDIR=$(pwd)/bin"

# Create a copy of our current target state and install some python modules
# that aren't available in apt. We copy these modules to our target at the end.
FROM icinga2-target AS pipinstalls

RUN apt-get update ;\
	apt-get install --no-install-recommends --no-install-suggests -y \
		python3-pip ;

# Removing the entire /usr/local/lib contents is extreme, but this keeps things
# clean for the copy operation later.
RUN rm -r /usr/local/lib/*;\
	pip3 install --no-cache-dir --break-system-packages \
    	boto3 boto3-assume click click-log click-option-group pendulum \
		pytest-testinfra typing-extensions ;

# The "lovely" stage needed for DBD::Oracle and other custom Perl stuff
FROM icinga2-target AS perlmodules

# install the needed modules for the compilation
RUN apt-get update ;\
	apt-get install --no-install-recommends --no-install-suggests -y \
		build-essential cpanminus expect ;

# download and set up the Oracle Instant Client packages
RUN	ORACLEARCH=$([ $(dpkg --print-architecture) = "amd64" ] && echo "x64" || echo $(dpkg --print-architecture) ) ;\
	curl -O -O https://download.oracle.com/otn_software/linux/instantclient/1925000/instantclient-sqlplus-linux.$ORACLEARCH-19.25.0.0.0dbru.zip \
	https://download.oracle.com/otn_software/linux/instantclient/1925000/instantclient-sdk-linux.$ORACLEARCH-19.25.0.0.0dbru.zip ;\
	mkdir -p /opt/oracle ;\
	unzip -n 'instantclient*.zip' -d /opt/oracle

# build DBD::Oracle
RUN ln -s /opt/oracle/instantclient/libclntshcore.so.19.1 /opt/oracle/instantclient/libclntshcore.so ;\
	ORACLE_HOME=/opt/oracle/instantclient cpanm --no-man-pages --notest DBD::Oracle ;

# Copy up the expect script for JMX4Perl
COPY jmx4perl.exp /

# Install JMX4Perl (just the jmx4perl and check_jmx4perl binaries)
RUN /usr/bin/expect /jmx4perl.exp

#########################
### END Custom Stages ###
#########################

# Switch back to our target image
FROM icinga2-target

# Copy the pip modules into the target
COPY --from=pipinstalls /usr/local/lib/ /usr/local/lib/

# Copy the Perl modules into the target (Some are in /usr/local/lib others are in /usr/local/share)
COPY --from=perlmodules /usr/local/ /usr/local/

# Some perl modules bundle check plugins, and they get installed to /usr/local/bin. Copy these to the plugins directory.
COPY --from=perlmodules /usr/local/bin/check_* /usr/lib/nagios/plugins/

# Copy extra check plugins into the target
COPY --from=build-plugins /check_oracle_health/bin/ /

# Switch the user back to icinga so things run cleanly
USER icinga
