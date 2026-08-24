FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends tesseract-ocr poppler-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

CMD ["sh", "-c", "gunicorn -k uvicorn.workers.UvicornWorker -w 2 -b 0.0.0.0:${PORT:-8000} --timeout 120 app.main:app"]
