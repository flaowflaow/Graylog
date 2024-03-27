#!/bin/bash
# Script d'installation d'un serveur de gestion de logs Graylog.
# Services : Graylog, ElasticSearch, MongoDB
  
# Installation des prérequis
sudo apt update && apt upgrade -y
sudo apt install apt-transport-https software-properties-common uuid-runtime pwgen dirmngr gnupg wget curl unzip net-tools openjdk-17-jre-headless -y

# Changement de la timezone
timedatectl set-timezone Europe/Paris


# Installation de MongoDB
curl -fsSL https://www.mongodb.org/static/pgp/server-6.0.asc | \
   sudo gpg -o /usr/share/keyrings/mongodb-server-6.0.gpg \
   --dearmor
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list
sudo apt-get update && sudo apt-get install -y mongodb-org

sudo systemctl daemon-reload
sudo systemctl enable mongod.service
sudo systemctl restart mongod.service


# Installation d'OpenSearch
curl -o- https://artifacts.opensearch.org/publickeys/opensearch.pgp | sudo gpg --dearmor --batch --yes -o /usr/share/keyrings/opensearch-keyring
echo "deb [signed-by=/usr/share/keyrings/opensearch-keyring] https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/apt stable main" | sudo tee /etc/apt/sources.list.d/opensearch-2.x.list
sudo apt-get update && sudo apt list -a opensearch
sudo OPENSEARCH_INITIAL_ADMIN_PASSWORD=$(tr -dc A-Z-a-z-0-9_@#%^-_=+ < /dev/urandom | head -c${1:-32}) apt-get install opensearch


# Graylog configuration pour Opensearch
sudo sed -i 's/#cluster.name: my-application/cluster.name: graylog/' /etc/opensearch/opensearch.yml
sudo sed -i 's/#node.name: node-1/node.name: node-1/' /etc/opensearch/opensearch.yml
sudo sed -i 's/#network.host: 192.168.0.1/network.host: 192.168.33.30/' /etc/opensearch/opensearch.yml
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


# Installation de Graylog
wget https://packages.graylog2.org/repo/packages/graylog-5.2-repository_latest.deb
sudo dpkg -i graylog-5.2-repository_latest.deb
sudo apt-get update && sudo apt-get install graylog-server 

# Configurer l'heure de l'utilisateur root
sudo sed -i 's@#root_timezone = UTC@root_timezone = Europe/Paris@' /etc/graylog/server/server.conf
# Configurer graylog
sudo sed -i 's/password_secret =.*/password_secret = $(pwgen -s 96 1)/g' /etc/graylog/server/server.conf
# Générer le mot de passe admin
sudo sed -i "s/root_password_sha2 =.*/root_password_sha2 = $(echo -n admin | sha256sum | cut -d" " -f1)/g" /etc/graylog/server/server.conf
# Configurer l'adresse IP
sudo sed -i "s/# Default: 127.0.0.1:9000/Default: 127.0.0.1:9000/g" /etc/graylog/server/server.conf
sudo sed -i "s/#http_bind_address = 127.0.0.1:9000/http_bind_address = 192.168.33.30:9000/g" /etc/graylog/server/server.conf
# Configurer le node ElasticSearch
sudo sed -i 's|#elasticsearch_hosts = http://node1:9200,http://user:password@node2:19200|elasticsearch_hosts = http://192.168.33.30:9200|g' /etc/graylog/server/server.conf
# Configurer le collecteur UDP
sudo sed -i "s/#inputbuffer_processors = 2/inputbuffer_processors = 2/g" /etc/graylog/server/server.conf
sudo sed -i "s/#processbuffer_processors = 5/processbuffer_processors = 5/g" /etc/graylog/server/server.conf
sudo sed -i "s/#outputbuffer_processors = 3/outputbuffer_processors = 3/g" /etc/graylog/server/server.conf
sudo sed -i "s/#udp_recvbuffer_sizes = 1048576/udp_recvbuffer_sizes = 1048576/g" /etc/graylog/server/server.conf



# Activation et démarrage de Graylog
sudo systemctl daemon-reload
sudo systemctl enable graylog-server.service
sudo systemctl restart graylog-server.service