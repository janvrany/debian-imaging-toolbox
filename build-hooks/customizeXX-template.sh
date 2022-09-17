#!/bin/bash
#
# Add comment here...
#
source "$(dirname $0)/../functions.sh"
config "$(dirname $0)/../config.sh" || error "Cannot read config.sh: $1"
config "$(dirname $0)/../config-local.sh"
ensure_ROOT $1

#
# Config variables
#
: ${CONFIG_TEMPLATE_VAR1:=default-value1}

#
# Add comment here...
#