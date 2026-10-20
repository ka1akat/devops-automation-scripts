import logging
import sys
from flask import Flask

app = Flask(__name__)

logging.basicConfig(
    stream=sys.stdout,
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)

@app.route("/")
def index():
    app.logger.info("Request to / received")
    return {"status": "ok", "message": "Hello from simple API"}

@app.route("/health")
def health():
    return {"status": "healthy"}

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
