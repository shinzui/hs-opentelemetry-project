# Pull latest changes from upstream hs-opentelemetry
pull-hs-opentelemetry:
    git subtree pull --prefix=hs-opentelemetry https://github.com/iand675/hs-opentelemetry main

# Push local changes to upstream hs-opentelemetry
push-hs-opentelemetry:
    git subtree push --prefix=hs-opentelemetry https://github.com/iand675/hs-opentelemetry main

# Show log of subtree changes for hs-opentelemetry
log-hs-opentelemetry:
    git log --oneline --graph -- hs-opentelemetry/

# Pull all upstream repos
pull-all: pull-hs-opentelemetry
