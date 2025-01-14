# install pull secret
OC=$(which oc)

NAMESPACE=mas-sso

$OC create ns ${NAMESPACE}

$OC project ${NAMESPACE}

$OC create secret docker-registry rhoas-pull-docker  \
    --docker-server=quay.io \
    --docker-username=${DOCKER_USER_NAME} \
    --docker-password=${DOCKER_PASSWORD} \
    --docker-email=example@example.com

# link the pull secret to default service account

$OC secrets link default rhoas-pull-docker --for=pull


#create the operator

$OC process -f mas-sso/sso-template.yaml -p NAMESPACE=${NAMESPACE} | $OC create -f -


#wait for the CRD
while [ $($OC get crd | grep keycloaks.keycloak.org | wc -l) != 1 ]
do
  sleep 1
  echo "waiting for keycloak CRD to be present"
done

#apply admin role to service account temp work around for a route host perm missing
#   - routes/custom-host

$OC adm policy add-role-to-user admin -z mas-sso-operator

$OC create -f mas-sso/keycloak.yaml

while [ "$($OC get keycloak mas-sso -n $NAMESPACE -o go-template={{.status.ready}})" != "true" ]
do
  sleep 3
  echo "MAS SSO is not ready. Current mas sso status message: $($OC get keycloak -n $NAMESPACE -o go-template={{.status.message}})"
done

echo "MAS SSO is ready $($OC get route keycloak -n $NAMESPACE -o go-template={{.spec.host}})"

$OC create -f mas-sso/realms/realm-rhoas.yaml
$OC create -f mas-sso/realms/realm-rhoas-kafka-sre.yaml

$OC create -f mas-sso/clients/strimzi-ui.yaml
$OC create -f mas-sso/clients/rhoas-cli.yaml
$OC create -f mas-sso/clients/kas-installer.yaml

if [ -n "${RH_USERNAME}" ] && [ -n "${RH_USER_ID}" ] && [ -n "${RH_ORG_ID}" ] ; then
    echo "Creating KAS cluster owner account"
    ${OC} process -f mas-sso/clients/owner-template.yaml -pRH_USERNAME=${RH_USERNAME} -pRH_USER_ID=${RH_USER_ID} -pRH_ORG_ID=${RH_ORG_ID} | oc create -f - -n ${NAMESPACE}
fi

sleep 10

sh ./mas-sso/kas.sh
sh ./mas-sso/kas-sre.sh
sh ./mas-sso/role-admin.sh
sh ./mas-sso/role-agent.sh
