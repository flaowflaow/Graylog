#!/bin/bash
# Script d'installation d'un serveur de gestion de logs Graylog.
# Services : Graylog 6.1, OpenSearch, MongoDB 8.0
# Création d'un certificat SSL autosigné
# Compatible avec Ubuntu 20.10 , 22.04 , 24.04


# Configuration réseau de la VM
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

# Créer le fichier de configuration Netplan en fournissant les détails

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

# Appliquer la configuration Netplan
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
curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | \
   sudo gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg \
   --dearmor
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/8.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list
sudo apt-get update && sudo apt-get install -y mongodb-org

sudo systemctl daemon-reload
sudo systemctl enable mongod.service
sudo systemctl restart mongod.service

sudo apt-mark hold mongodb-org

echo "L'installation de MongoDB s'est déroulée correctement."

sleep 5


### Installation de Data Node
if grep -q "^vm.max_map_count" /etc/sysctl.conf; then
    sudo sed -i 's/^vm.max_map_count.*/vm.max_map_count=262144/' /etc/sysctl.conf
else
    sudo sed -i '$a vm.max_map_count=262144' /etc/sysctl.conf
fi
sudo sysctl -p

wget https://packages.graylog2.org/repo/packages/graylog-6.1-repository_latest.deb
sudo dpkg -i graylog-6.1-repository_latest.deb
sudo apt-get update
sudo apt-get install graylog-datanode

# Générer et assigner une valeur à la variable password_secret
password_secret=$(< /dev/urandom tr -dc 'A-Za-z0-9' | head -c96)

# Utiliser la variable password_secret dans la commande sed
sudo sed -i "s/^password_secret.*/password_secret = $password_secret/" /etc/graylog/datanode/datanode.conf


# Graylog configuration pour Opensearch
sudo sysctl -w vm.max_map_count=262144
echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf

# Activation et redémarrage
sudo systemctl enable graylog-datanode.service
sudo systemctl start graylog-datanode

echo "L'installation de Data Node s'est déroulée correctement."

sleep 5

### Installation de Graylog
sudo apt install -y graylog-server 

# Configurer l'heure de l'utilisateur root
sudo sed -i 's@#root_timezone = UTC@root_timezone = Europe/Paris@' /etc/graylog/server/server.conf
# Configurer graylog
sudo sed -i "s/^password_secret.*/password_secret = $password_secret/" /etc/graylog/server/server.conf
# Générer le mot de passe admin
#!/bin/bash

# Boucle tant que les mots de passe ne correspondent pas
while true; do
    echo -n "Enter Graylog admin Password: "
    read -s password1
    echo
    echo -n "Confirm Graylog admin Password: "
    read -s password2
    echo

    # Si les mots de passe correspondent, on sort de la boucle
    if [ "$password1" = "$password2" ]; then
        root_password_sha2=$(echo -n "$password1" | sha256sum | cut -d" " -f1)
        sudo sed -i "s/^root_password_sha2.*/root_password_sha2 = $root_password_sha2/" /etc/graylog/server/server.conf
        echo "Password updated successfully in /etc/graylog/server/server.conf"
        break
    else
        # Si les mots de passe ne correspondent pas, demander de recommencer
        echo "Passwords do not match. Please try again."
    fi
done


sleep 10


# Configurer l'adresse IP
# sudo sed -i "s/# Default: 127.0.0.1:9000/Default: 127.0.0.1:9000/g" /etc/graylog/server/server.conf
sudo sed -i "s/#http_bind_address = 127.0.0.1:9000/http_bind_address = $ip_address:9000/g" /etc/graylog/server/server.conf

sudo systemctl daemon-reload
sudo systemctl enable graylog-server.service
sudo systemctl restart graylog-server.service

echo "L'installation de Graylog s'est déroulée correctement."

sleep 5

echo "Fin de l'installation, merci d'avoir utilisé ce script."