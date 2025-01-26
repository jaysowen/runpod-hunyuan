# ComfyUI HunyuanVideo API Server

This project provides a containerized environment for running the HunyuanVideo model through ComfyUI, including a web-based VS Code editor for development. It's designed to be deployed as a serverless API endpoint.

## Features

- 🎥 HunyuanVideo text-to-video generation
- 💻 Built-in web-based VS Code editor
- 🐋 Full Docker containerization
- 🚀 RunPod serverless compatibility
- 🔄 Automatic model downloads
- 🛠️ Pre-configured workflow

## Prerequisites

- Docker installed on your system
- NVIDIA GPU with CUDA support
- At least 8GB of GPU memory
- Docker NVIDIA Container Toolkit installed

## Quick Start

1. Clone the repository:
```bash
git clone <repository-url>
cd <repository-name>
```

2. Build the Docker image:
```bash
docker build -t hunyuan-video-server .
```

3. Run the container:
```bash
docker run -d \
  --gpus all \
  -p 8080:8080 \
  -p 3000:3000 \
  hunyuan-video-server
```

## Accessing the Development Environment

- VS Code Web Interface: `http://localhost:8080`
- Default Password: `comfyui`

## API Usage

The server accepts POST requests with the following format:

```json
{
    "input": {
        "prompt": "Your video description",
        "num_frames": 16,
        "fps": 8
    }
}
```

Example using cURL:
```bash
curl -X POST http://localhost:3000/run \
  -H "Content-Type: application/json" \
  -d '{"input": {"prompt": "A cat walking", "num_frames": 16, "fps": 8}}'
```

## Project Structure

```
.
├── Dockerfile              # Container configuration
├── handler.py             # RunPod serverless handler
├── workflow.json          # ComfyUI workflow configuration
└── README.md             # This file
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| CODE_SERVER_PASSWORD | VS Code web interface password | comfyui |
| PORT | API server port | 3000 |

## Models

The following models are automatically downloaded during container build:

- HunyuanVideo Text-to-Video Model (BF16)
- CLIP Text Encoder
- LLaVA LLaMa3 Text Encoder
- HunyuanVideo VAE

## Development

1. Access the web VS Code interface at `http://localhost:8080`
2. Login with the default password: `comfyui`
3. The workspace is pre-configured with all necessary files
4. Live changes can be made to `handler.py` and `workflow.json`

## Troubleshooting

Common issues:

1. **GPU Memory Error**: Ensure you have at least 8GB of GPU memory available
2. **Port Conflicts**: Make sure ports 8080 and 3000 are not in use
3. **CUDA Issues**: Verify NVIDIA drivers and Docker NVIDIA toolkit are properly installed

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details

## Acknowledgments

- ComfyUI Team
- HunyuanVideo Model Creators
- RunPod for the serverless infrastructure

