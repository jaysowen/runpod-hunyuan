# RunPod Hunyuan Template

A custom RunPod template for running Hunyuan video generation with ComfyUI and VS Code.

## Repository Structure
```
.
├── .github/
│   └── workflows/
│       └── docker-publish.yml
├── docker/
│   ├── Dockerfile
│   ├── setup.sh
│   └── start.sh
├── workflow/
│   └── workflow.json
├── .gitignore
└── README.md
```

## Files Overview

### `.github/workflows/docker-publish.yml`
Handles automated building and publishing of the Docker image to Docker Hub.

### `docker/Dockerfile`
Contains the main Docker image configuration.

### `docker/setup.sh`
Sets up ComfyUI, custom nodes, and downloads required models.

### `docker/start.sh`
Startup script that runs when the container starts.

### `workflow/workflow.json`
The ComfyUI workflow configuration.

## Setup Instructions

1. Fork this repository
2. Add your Docker Hub secrets to GitHub:
   - `DOCKERHUB_USERNAME`
   - `DOCKERHUB_TOKEN`
3. Update the Docker image name in the workflow file
4. Push changes to trigger the build

## Usage

Use this template in RunPod by selecting the custom Docker image:
`your-dockerhub-username/hunyuan-comfyui:latest`

### RunPod Template Settings
- Container Disk: 20GB minimum
- Volume Disk: 20GB minimum
- Ports: 8188 (ComfyUI), 8080 (VS Code)