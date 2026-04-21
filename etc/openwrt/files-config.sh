#!/bin/sh

# Collect all the files that a regular OpenWrt system usually backs up.
#
# If you want to exclude some files, you can use grep. For example, the following 
# command will ignore all transient Let's Encrypt generated files:
#
#     /sbin/sysupgrade -l | grep -vE '^(/etc/ssl|/etc/acme)'
#
# If you want to include additional files, just add a command listing the needed files.
# For example:
#
#     find /root/ -type f -name \*hosts
#

/sbin/sysupgrade -l