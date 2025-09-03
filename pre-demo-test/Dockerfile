FROM arm32v7/python:3.9-slim
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt || true
CMD ["python", "-u", "main.py"]
