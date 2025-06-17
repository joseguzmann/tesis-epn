FROM python:3.11-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git \
      docker.io \
      curl \
 && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/binary-knight/logwhisperer /opt/logwhisperer \
 && pip install --no-cache-dir -r /opt/logwhisperer/requirements.txt

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
WORKDIR /opt/logwhisperer

ENTRYPOINT ["/entrypoint.sh"]