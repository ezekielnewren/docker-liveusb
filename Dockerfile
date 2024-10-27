FROM rockylinux:9.3

# RUN dnf check-update || true
RUN dnf install -y epel-release
RUN dnf install -y dumb-init

COPY copy /copy
# RUN mv /copy/.profile /root/.profile
# RUN mv /copy/*.sh /usr/local/bin/

# RUN dnf install -y losetup
# RUN apk add nano file losetup alpine-conf squashfs-tools efibootmgr rsync cpio

ENTRYPOINT ["dumb-init", "--", "bash", "-c"]
CMD ["bash"]

