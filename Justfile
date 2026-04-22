# List available recipes
default:
    @just --list

# Update hs-opentelemetry subtree from upstream main
update-hs-opentelemetry:
    git subtree pull --prefix=hs-opentelemetry https://github.com/iand675/hs-opentelemetry.git main

# Update all subtrees from upstream
update-all: update-hs-opentelemetry

# Show commit log from hs-opentelemetry upstream
log-hs-opentelemetry:
    git fetch https://github.com/iand675/hs-opentelemetry.git main
    git log --oneline FETCH_HEAD
