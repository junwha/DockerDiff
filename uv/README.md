# Efficient Docker Storage Management with Pre-built, Torch-Shared uv Images

### Problem Definition

When multiple users on a server repeatedly build their own Docker images, it results in massive duplicated storage usage. Specifically, repeated installations of PyTorch (which exceeds 5GB) can rapidly consume server disk space.

### Solution

We provide a monolithic base image with various PyTorch versions and essential libraries pre-installed. Users can simply build their images on top of this base.

  * **Zero-Copy Torch:** PyTorch is already installed in the base layer.
  * **Symlink & Inheritance:** Uses `uv` to link existing installations, so your project only takes up space for *additional* packages.

### Usage

### 1. Docker file example

```dockerfile
FROM junwha/ddiff-base:cu12.4.1-py3.10-torch-251205

WORKDIR /<your workspace>

# 1. Initialize venv linked to a specific Torch version
# (Note: This creates a symlink to the base image's venv, thus only one project per torch version is recommended)
RUN uv_init_torch2.5.1

# 2. Install additional packages (without torch)
COPY pyproject.yaml /<your workspace>
RUN uv pip install . --no-cache --no-install torch --no-install torchvision --no-install torchaudio

```

### 2. Running Commands Inside the container
you can use standard uv commands. The environment is automatically detected via the .venv link.

```uv run python example.py```

# Base Images
### Common Packages
* **Python Libraries**
    * **Data & Science:** numpy pandas scipy scikit-learn matplotlib seaborn
    * **Tools:** jupyterlab ipykernel tqdm rich
    * **CV & Utils:** opencv-python-headless pillow einops safetensors

* **System Libraries**
    * **Basic Utils:** git ffmpeg vim git bzip2 tmux wget tar htop curl
    * **X11 Utils:** mesa-utils x11-apps freeglut3-dev libglu1-mesa-dev mesa-common-dev libxkbfile-dev libgl1-mesa-glx libgl1
    * **Build Tools:** gcc-12 g++-12 ninja-build cmake build-essential 
    * **Profiler:** Nsight System 2024
## Releases
**Image Tag:** `junwha/ddiff-base:cu12.4.1-py3.10-torch-251205`
  * **Python:** 3.10
  * **Pre-installed PyTorch Versions:** 2.4.1, 2.5.1, 2.6.0, 2.7.1, 2.9.0
  * **Compute Capabilities**: 7.0 7.5 8.0 8.6 8.9 9.0+PTX

