# update + freeRDP
sudo apt update && sudo apt install -y freerdp2-x11
sudo apt install -y docker.io containerd.io docker-compose
sudo systemctl enable --now docker
sudo systemctl start docker
sudo systemctl start dockerd
sudo systemctl start containerd
sudo systemctl enable xrdp
sudo systemctl enable xrdp-sesman
sudo systemctl start xrdp
sudo systemctl start xrdp-sesman
# make a new user for rdp - you can only have one active session, so its better to just make a new user just for this
sudo useradd -m -s /bin/bash guacusr0
sudo password guacusr0
sudo usermod -aG sudo guacusr0
sudo -u guacusr0 bash -c 'echo "exec /usr/bin/gnome-session" > /home/guacusr0/.Xclients; chmod +x /home/guacusr0/.Xclients; chown guacusr0:guacusr0 /home/guacusr0/.Xclients'
echo "switch to new user for rest of setup"
su guacusr0

#ngrok install
curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
  | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null \
  && echo "deb https://ngrok-agent.s3.amazonaws.com bookworm main" \
  | sudo tee /etc/apt/sources.list.d/ngrok.list \
  && sudo apt update \
  && sudo apt install ngrok

echo -ne "If you havent already - sign up for ngrok then navigate to:
https://dashboard.ngrok.com/get-started/setup/linux"
read -p "Paste the full Ngrok auth command here: " NGROK_AUTH
bash $NGROK_AUTH

sudo systemctl enable --now xrdp

# open firewall for RDP (ufw)
sudo apt install -y ufw
sudo ufw allow 3389/tcp
sudo ufw reload || true


# allow current user to use docker (log out/in or run newgrp)
sudo usermod -aG docker guacusr0
newgrp docker || true

# prepare guacamole config dir and run all-in-one container (bind to localhost)
sudo mkdir -p /opt/guac
sudo chown guacusr0:guacusr0 /opt/guac
sudo docker run -d --name guac --restart unless-stopped \
  -p 127.0.0.1:8080:8080 \
  -e TZ="America/Los_Angeles" \
  -e EXTENSIONS="auth-totp" \
  -v /opt/guac:/config \
  flcontainers/guacamole &

# quick checks
# Get docker0 bridge IP
DOCKERBRIDGE_IP=$(ip -4 addr show docker0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
# Guess container IP = bridge IP + 1 (last octet incremented)
CONTAINERIP=$(echo "$DOCKERBRIDGE_IP" | awk -F. '{print $1"."$2"."$3"."$4+1}')

# List possible endpoints
CANDIDATES=(
    "127.0.0.1:8080"
    "${DOCKERBRIDGE_IP}:8080"
    "${CONTAINERIP}:8080"
)

# Loop through and find first responsive endpoint
for addr in "${CANDIDATES[@]}"; do
    if curl -s --max-time 2 "http://${addr}" | grep -q "<html"; then
        echo "Guacamole is available at: ${addr}"
        SELECTED="$addr"
        break
    fi
done

if [ -z "$SELECTED" ]; then
    echo "No Guacamole endpoint responded."
    exit 1
fi

# Start ngrok with found address
ngrok http "http://${SELECTED}"

echo -e "
Next steps:
	1. Navigate to the guacamole web service at "http://${SELECTED}"
	2. Log in using guacadmin:guacadmin
	3. Navigate to settings, change the password for the admin user (recommened 120+ chat password)
	4. Create a new user, and a new group - the only permission should be to connect to sessions
	5. Go to connections --> new connections:
	REQUIRED - Leave all others blank unless you know what you're doing
		Section name: 
		EDIT CONNECTION	
			- Name:
			- Location: (leave as root)
			- Protocol: Change to RDP
		PARAMETERS
			- Hostname: your hostname or ip of RDP system
			- Port: 3389 unless custom config
			- Encryption: ANY
		AUTHENTICATION
			- Username: guacusr0
			- Password: your new password for guacusr0
	6. Go to main page - look for RDP session and try to connect.
	7. Log in with other user and validate ability to connect. Don't use admin user remotely.
"
