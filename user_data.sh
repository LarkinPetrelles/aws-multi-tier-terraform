#!/bin/bash
yum update -y
amazon-linux-extras install -y python3.8
pip3 install flask

cat > /home/ec2-user/app.py <<'EOF'
from flask import Flask
import os

app = Flask(__name__)

@app.route("/")
def index():
    return f"Multi-Tier Demo: Hello from instance {os.uname().nodename}\n"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
EOF

chown ec2-user:ec2-user /home/ec2-user/app.py
nohup python3 /home/ec2-user/app.py > /var/log/app.log 2>&1 &
