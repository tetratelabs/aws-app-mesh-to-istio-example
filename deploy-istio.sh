#!/bin/bash

set -eo pipefail

if [ -z $AWS_ACCOUNT_ID ]; then
    echo "AWS_ACCOUNT_ID environment variable is not set."
    exit 1
fi

if [ -z $AWS_DEFAULT_REGION ]; then
    echo "AWS_DEFAULT_REGION environment variable is not set."
    exit 1
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
PROJECT_NAME="howto-k8s-http2"
APP_NAMESPACE=${PROJECT_NAME}
APP_ISTIO_NAMESPACE=${APP_NAMESPACE}-istio
ECR_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"
ECR_IMAGE_PREFIX="${ECR_URL}/${PROJECT_NAME}"
CLIENT_APP_IMAGE="${ECR_IMAGE_PREFIX}/color_client"
COLOR_APP_IMAGE="${ECR_IMAGE_PREFIX}/color_server"
AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d. -f1)

error() {
    echo $1
    exit 1
}


check_istio_k8s() {
    numberIstiodReplicas=$(kubectl get deployment -n istio-system istiod -o json | jq -r .status.readyReplicas)
    if [ $numberIstiodReplicas -gt 0 ]; then
        echo "istiod check passed! $nuberIstiodReplicas running"
    else
        error "$PROJECT_NAME requires istio to be deployed first. See https://tetratelabs.github.io/tid-addon-workshop/4_deploy_tid_addon/"
    fi
}

ecr_login() {
    if [ $AWS_CLI_VERSION -gt 1 ]; then
        aws ecr get-login-password --region ${AWS_DEFAULT_REGION} --profile $AWS_PROFILE | \
            docker login --username AWS --password-stdin ${ECR_URL}
    else
        $(aws ecr get-login --no-include-email --profile $AWS_PROFILE)
    fi
}

deploy_images() {
    ecr_login
    for app in color_client color_server; do
        aws ecr describe-repositories --repository-name $PROJECT_NAME/$app --profile $AWS_PROFILE >/dev/null 2>&1 || aws ecr create-repository --profile $AWS_PROFILE --repository-name $PROJECT_NAME/$app >/dev/null
        docker build -t ${ECR_IMAGE_PREFIX}/${app} ${DIR}/${app} --build-arg GO_PROXY=${GO_PROXY:-"https://proxy.golang.org"}
        docker push ${ECR_IMAGE_PREFIX}/${app}
    done
}

deploy_app() {
    EXAMPLES_OUT_DIR="${DIR}/_output/"
    mkdir -p ${EXAMPLES_OUT_DIR}
    eval "cat <<EOF
$(<${DIR}/istio/manifest-istio.yaml.template)
EOF
" >${EXAMPLES_OUT_DIR}/manifest-istio.yaml

    kubectl apply -f ${EXAMPLES_OUT_DIR}/manifest-istio.yaml
}

main() {
    check_istio_k8s

    if [ -z $SKIP_IMAGES ]; then
        echo "deploy images..."
        deploy_images
    fi

    deploy_app
}

main
