#!/usr/bin/env bash
# Fake df producing fixed `df -B1` output. The bar's DiskUsage plugin parses
# header + rows; values match a 500GB / drive at 33% used.
echo "Filesystem        1B-blocks         Used    Available Use% Mounted on"
echo "/dev/fake     524288000000 174762666666 349525333334  34% /"
