# This extends the base Icinga2 container image to include custom libraries for
# other check plugins that are added in later in a volume.

# Pull our base image in. This instance of the image will be the target to which
# we apply our modifications
FROM ghcr.io/srvrguy/icinga2:v2.14.2 AS icinga2-target

# The base image switches to the icinga user, we need to switch to root to do
# our additions.
USER root

# Additional packages installed via apt.
# Keep package names in alphabetical order
RUN apt-get update ;\
	apt-get install --no-install-recommends --no-install-suggests -y \
		libxml-simple-perl libwww-perl python3-bson python3-dnspython \
		python3-pymongo python3-pytest;\
	apt-get clean ;\
	rm -vrf /var/lib/apt/lists/*

###########################
### BEGIN Custom Stages ###
###########################
# Things we can't do cleanly in our target happen now.

# Create a copy of our current target state and install some python modules
# that aren't available in apt. We copy these modules to our target at the end.
FROM icinga2-target AS pipinstalls

RUN apt-get update ;\
	apt-get install --no-install-recommends --no-install-suggests -y \
		python3-pip ;

# Removing the entire /usr/local/lib contents is extreme, but this keeps things
# clean for the copy operation later.
RUN rm -r /usr/local/lib/*;\
	pip3 install --no-cache-dir \
    	boto3 boto3-assume click pendulum pytest-testinfra typing-extensions ;

#########################
### END Custom Stages ###
#########################

# Switch back to our target image
FROM icinga2-target

# Copy the pip modules into the target
COPY --from=pipinstalls /usr/local/lib/ /usr/local/lib/

# Switch the user back to icinga so things run cleanly
USER icinga
