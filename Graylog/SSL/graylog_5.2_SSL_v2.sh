#!/bin/bash
# Script d'installation d'un serveur de gestion de logs Graylog.
# Services : Graylog, OpenSearch, MongoDB
# Création d'un certificat SSL autosigné


# Afficher les interfaces réseau disponibles

echo "Interfaces réseau disponibles :"

ip link show | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}'

read -p "Entrez l'interface reseau a configurer: " selected_interface

##### DEMANDE DES VARIABLES PERSONNALISÉES #####
echo "Veuillez fournir les informations suivantes :"
read -p "Adresse IP: " ip_address
read -p "Masque de sous reseau (e.g., 24 for /24): " subnet_mask
read -p "Passerelle par defaut: " gateway
read -p "Serveur DNS primaire: " dns_primary
read -p "Serveur DNS secondaire (en option): " dns_secondary
read -p "Votre domaine (ex: yourdomain.local): "  domain
read -p "Région : " state
read -p "Ville : " city
read -p "Lieu : " location

# Create a Netplan configuration file with the provided details

cat > /etc/netplan/01-network-config.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $selected_interface:
      addresses: [$ip_address/$subnet_mask]
      routes:
        - to: 0.0.0.0/0
          via: $gateway
          on-link: true
      nameservers:
        addresses: [$dns_primary, $dns_secondary]
EOF

sudo chmod 600 /etc/netplan/01-network-config.yaml 

# Apply the Netplan configuration
sudo netplan apply

echo "La configuration réseau s'est déroulée correctement."

sleep 5

##### MODIFICATION DES VARIABLES #####
hostname="srv-graylog"
fqdn="$hostname.$domain"

# Modification du hostname
sudo hostnamectl set-hostname "$fqdn"
sudo hostname "$fqdn"

# Installation des prérequis
sudo apt update && apt upgrade -y
sudo apt install -y apt-transport-https software-properties-common uuid-runtime pwgen dirmngr gnupg wget curl unzip net-tools openjdk-17-jre-headless net-tools 

# Changement de la timezone
sudo timedatectl set-timezone Europe/Paris


### Installation de MongoDB
curl -fsSL https://www.mongodb.org/static/pgp/server-6.0.asc | \
 sudo gpg -o /usr/share/keyrings/mongodb-server-6.0.gpg \
 --dearmor
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list
sudo apt-get update && sudo apt-get install -y mongodb-org

sudo systemctl daemon-reload
sudo systemctl enable mongod.service
sudo systemctl restart mongod.service

echo "L'installation de MongoDB s'est déroulée correctement."

sleep 5


### Installation d'OpenSearch
curl -o- https://artifacts.opensearch.org/publickeys/opensearch.pgp | sudo gpg --dearmor --batch --yes -o /usr/share/keyrings/opensearch-keyring
echo "deb [signed-by=/usr/share/keyrings/opensearch-keyring] https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/apt stable main" | sudo tee /etc/apt/sources.list.d/opensearch-2.x.list
sudo apt-get update && sudo apt list -a opensearch
sudo OPENSEARCH_INITIAL_ADMIN_PASSWORD=$(tr -dc A-Z-a-z-0-9_@#%^-_=+ < /dev/urandom | head -c${1:-32}) apt-get install opensearch

# Graylog configuration pour Opensearch
sudo sed -i 's/#cluster.name: my-application/cluster.name: graylog/' /etc/opensearch/opensearch.yml
sudo sed -i 's/#node.name: node-1/node.name: node-1/' /etc/opensearch/opensearch.yml
sudo sed -i "s/#network.host: 192.168.0.1/network.host: $ip_address/" /etc/opensearch/opensearch.yml
sudo sed -i '/#action.destructive_requires_name: true/a action.auto_create_index: false' /etc/opensearch/opensearch.yml
sudo sed -i '/# WARNING: revise all the lines below before you go into production/a plugins.security.disabled: true' /etc/opensearch/opensearch.yml
sudo sed -i '/plugins.security.disabled: true/a indices.query.bool.max_clause_count: 32768' /etc/opensearch/opensearch.yml
sudo sed -i '/#discovery.seed_hosts:/a discovery.seed_hosts: "127.0.0.1"' /etc/opensearch/opensearch.yml
sudo sed -i '/discovery.seed_hosts: "127.0.0.1"/a discovery.type: single-node' /etc/opensearch/opensearch.yml

sudo sysctl -w vm.max_map_count=262144
echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf

# Activation et redémarrage
sudo systemctl daemon-reload
sudo systemctl enable opensearch.service
sudo systemctl restart opensearch.service

echo "L'installation d'OpenSearch s'est déroulée correctement."

sleep 5

### Installation de Graylog
wget https://packages.graylog2.org/repo/packages/graylog-5.2-repository_latest.deb
sudo dpkg -i graylog-5.2-repository_latest.deb
sudo apt-get update && sudo apt-get install -y graylog-server 

# Configurer l'heure de l'utilisateur root
sudo sed -i 's@#root_timezone = UTC@root_timezone = Europe/Paris@' /etc/graylog/server/server.conf
# Configurer graylog
sudo sed -i 's/password_secret =.*/password_secret = $(pwgen -s 96 1)/g' /etc/graylog/server/server.conf
# Générer le mot de passe admin
sudo sed -i "s/root_password_sha2 =.*/root_password_sha2 = $(echo -n admin | sha256sum | cut -d" " -f1)/g" /etc/graylog/server/server.conf
# Configurer l'adresse IP
sudo sed -i "s/# Default: 127.0.0.1:9000/Default: 127.0.0.1:9000/g" /etc/graylog/server/server.conf
sudo sed -i "s/#http_bind_address = 127.0.0.1:9000/http_bind_address = $ip_address:9000/g" /etc/graylog/server/server.conf
# Configurer le node ElasticSearch
sudo sed -i "s|#elasticsearch_hosts = http://node1:9200,http://user:password@node2:19200|elasticsearch_hosts = http://$ip_address:9200|g" /etc/graylog/server/server.conf
# Configurer le collecteur UDP
sudo sed -i "s/#inputbuffer_processors = 2/inputbuffer_processors = 2/g" /etc/graylog/server/server.conf
sudo sed -i "s/#processbuffer_processors = 5/processbuffer_processors = 5/g" /etc/graylog/server/server.conf
sudo sed -i "s/#outputbuffer_processors = 3/outputbuffer_processors = 3/g" /etc/graylog/server/server.conf
sudo sed -i "s/#udp_recvbuffer_sizes = 1048576/udp_recvbuffer_sizes = 1048576/g" /etc/graylog/server/server.conf

### Génération des certficats SSL et configuration HTTPS
# Création du dossier de destination des certificats
sudo mkdir /etc/graylog/server/certs
cd /etc/graylog/server/certs
sudo chmod 755 /etc/graylog/server/certs/
# Création du fichier de configuration pour openssl
sudo cat <<EOF > /etc/graylog/server/certs/openssl-graylog.cnf
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no
[req_distinguished_name]
C = FR
ST = $state
L = $city
O = $location
OU = Supervision
CN = $fqdn
[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
IP.1 = $ip_address 
DNS.1 = $fqdn # (nom dns de mon serveur on peut aussi l'ajouter dans le fichier /etc/hosts)   
EOF
# Génération du certificat au format x.509 et la clé privé au format PKSC#5 
sudo openssl req -x509 -days 365 -nodes -newkey rsa:2048 -config openssl-graylog.cnf -keyout pkcs5-privatekey.pem -out graylog-certificate.pem
# Conversion de la clé privée en PKCS#8 (sans mot de passe)
sudo openssl pkcs8 -in pkcs5-privatekey.pem -topk8 -nocrypt -out graylog-privatekey.pem
# Importation du certificat dans le java keystore
sudo keytool -importcert -keystore /usr/lib/jvm/java-17-openjdk-amd64/lib/security/cacerts -storepass changeit -alias graylog-selfsigned-certificate -file /etc/graylog/server/certs/graylog-certificate.pem -noprompt
sudo keytool -importcert -keystore /usr/share/graylog-server/jvm/lib/security/cacerts -storepass changeit -alias graylog-selfsigned-certificate -file /etc/graylog/server/certs/graylog-certificate.pem -noprompt
# Droits sur les certifcats
sudo chmod 644 /etc/graylog/server/certs/*
# Modification du fichier de configuration de Graylog
sudo sed -i 's|#http_enable_tls = true|http_enable_tls = true|g' /etc/graylog/server/server.conf
sudo sed -i 's|#http_tls_cert_file = /path/to/graylog.crt|http_tls_cert_file = /etc/graylog/server/certs/graylog-certificate.pem|g' /etc/graylog/server/server.conf
sudo sed -i 's|#http_tls_key_file = /path/to/graylog.key|http_tls_key_file = /etc/graylog/server/certs/graylog-privatekey.pem|g' /etc/graylog/server/server.conf
sudo sed -i "s/#http_bind_address = 127.0.0.1:9000/http_bind_address = $ip_address:9000/g" /etc/graylog/server/server.conf
# Modification du fichier de configuration d'Opensearch
sudo sed -i "/http_bind_address = $ip_address:9000/a http_bind_address = $fqdn:9000" /etc/opensearch/opensearch.yml

sudo systemctl daemon-reload
sudo systemctl enable graylog-server.service
sudo systemctl restart graylog-server.service

echo "L'installation de Graylog s'est déroulée correctement."

sleep 5

echo "Fin de l'installation, merci d'avoir utilisé ce script."