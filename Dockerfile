# Use the official Elixir image based on Debian
FROM elixir:1.18.3-otp-27

# Install system dependencies
# - python3, python3-pip, python3-venv for the Python subproject
# - libgl1, libglib2.0-0 for OpenCV
# - build-essential, git for compiling Elixir dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    libgl1 \
    libglib2.0-0 \
    build-essential \
    git \
    && rm -rf /var/lib/apt/lists/*

# Set working directory inside the container
WORKDIR /app

# Install Hex and Rebar (Elixir package managers)
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build environment to dev (default, can be overridden)
ENV MIX_ENV=dev

# Copy only mix files first to cache dependencies compilation
COPY mix.exs mix.lock ./
COPY apps/vehiscan/mix.exs ./apps/vehiscan/
COPY apps/vehiscan_web/mix.exs ./apps/vehiscan_web/

# Download Elixir dependencies
RUN mix deps.get

# Copy the rest of the application files
COPY . .

# Setup Python virtual environment inside the expected directory
# and install the required AI/ML dependencies
RUN python3 -m venv proyecto_sistema_inteligente/.venv && \
    ./proyecto_sistema_inteligente/.venv/bin/pip install --upgrade pip && \
    ./proyecto_sistema_inteligente/.venv/bin/pip install \
    ultralytics \
    easyocr \
    opencv-python-headless \
    pandas \
    kedro==1.3.1 \
    kedro-datasets \
    jupyterlab \
    notebook \
    ipython

# Build and compile Tailwind/Esbuild assets and compile Phoenix apps
RUN mix assets.setup && \
    mix assets.build && \
    mix compile

# Expose the default Phoenix port
EXPOSE 4000

# Command to run on container start (migrations + start server)
CMD ["/bin/sh", "-c", "mix ecto.migrate && mix phx.server"]
