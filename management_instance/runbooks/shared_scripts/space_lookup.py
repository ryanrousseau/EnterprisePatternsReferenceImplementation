# This script exists for those scenarios where the tenant space is created as part of the same process that
# attempts to populate the space. The tenant space ID variable, saved when the space is created, won't be refreshed
# in the middle of the deployment, so we query it directly.

import json
import urllib.request
import urllib.parse
import os
import sys
import time

# If this script is not being run as part of an Octopus step, return variables from environment variables.
if "get_octopusvariable" not in globals():
    def get_octopusvariable(variable):
        if variable == 'Octopus.Deployment.Tenant.Name':
            return os.environ['OCTOPUS_TENANT_NAME']

        return ""

# If this script is not being run as part of an Octopus step, just print any set variable to std out.
if "set_octopusvariable" not in globals():
    def set_octopusvariable(variable):
        print(variable)

url = 'http://octopus:8080/api/Spaces?partialName=' + \
      urllib.parse.quote(get_octopusvariable('Octopus.Deployment.Tenant.Name'))
headers = {
    "X-Octopus-ApiKey": "API-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    'Accept': 'application/json'
}
request = urllib.request.Request(url, headers=headers)

# Retry the request for up to a minute. This is because under heavy load Octopus may not respond correctly.
for x in range(12):
    response = urllib.request.urlopen(request)
    if response.getcode() == 200:
        break
    time.sleep(5)

data = json.loads(response.read().decode("utf-8"))

space = [x for x in data['Items'] if x['Name'] == get_octopusvariable('Octopus.Deployment.Tenant.Name')]

if len(space) != 0:
    print('Matched tenant name to space')
    set_octopusvariable("SpaceID", space[0]['Id'])
else:
    print('Failed to match tenant name to space')
    sys.exit(1)
