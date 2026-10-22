import sys
import logging
from datetime import datetime
from flask import Flask

app = Flask(__name__)
logging.getLogger("werkzeug").disabled = True

@app.route("/time")
def get_time():
    now = datetime.now().isoformat()
    print(f"{now} INFO GET /time")
    return {"time": now}

@app.route("/error")
def get_error():
    now = datetime.now().isoformat()
    print(f"{now} ERROR something went wrong", file=sys.stderr)
    return {"error": "something went wrong"}, 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
