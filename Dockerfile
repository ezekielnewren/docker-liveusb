FROM alpine:3.19

RUN apk add dumb-init bash

COPY copy /copy
# RUN mv /copy/.profile /root/.profile
# RUN mv /copy/*.sh /usr/local/bin/

RUN apk add losetup
# RUN apk add nano file losetup alpine-conf squashfs-tools efibootmgr rsync cpio

ENTRYPOINT ["dumb-init", "--", "bash", "-c"]
CMD ["bash"]
