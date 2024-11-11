#!/bin/bash
# Script d'installation d'un serveur de gestion de logs Graylog.
# Services : Graylog 6.1, OpenSearch, MongoDB 8.0
# Création d'un certificat SSL autosigné
# Compatible avec Ubuntu 20.10 , 22.04 , 24.04


# Configuration réseau de la VM
# Fonction principale
function config_network() {
    # Afficher les interfaces réseau disponibles
    echo "Interfaces réseau disponibles :"
    interfaces=$(ip link show | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}')

    # Affichage des interfaces disponibles dans un format lisible
    echo "$interfaces"

    # Demander à l'utilisateur de sélectionner l'interface réseau
    read -p "Entrez l'interface réseau à configurer (par exemple: eth0, ens33): " selected_interface

    ##### DEMANDE DES VARIABLES PERSONNALISÉES #####
    echo "Veuillez fournir les informations suivantes :"
    read -p "Adresse IP: " ip_address
    read -p "Masque de sous réseau (e.g., 24 pour /24): " subnet_mask
    read -p "Passerelle par défaut: " gateway
    read -p "Serveur DNS primaire: " dns_primary
    read -p "Serveur DNS secondaire (en option): " dns_secondary
    read -p "Votre domaine (ex: yourdomain.local): " domain
    read -p "Région : " state
    read -p "Ville : " city
    read -p "Lieu : " location

    # Afficher un résumé des informations saisies
    echo "Voici les informations que vous avez fournies :"
    echo "---------------------------------------------------"
    echo "Interfaces réseau disponibles :"
    echo "$interfaces"
    echo "---------------------------------------------------"
    echo "Interface réseau sélectionnée : $selected_interface"
    echo "Adresse IP : $ip_address"
    echo "Masque de sous réseau : $subnet_mask"
    echo "Passerelle par défaut : $gateway"
    echo "Serveur DNS primaire : $dns_primary"
    echo "Serveur DNS secondaire : $dns_secondary"
    echo "Votre domaine : $domain"
    echo "Région : $state"
    echo "Ville : $city"
    echo "Lieu : $location"
    echo "---------------------------------------------------"

    # Demander une confirmation
    read -p "Voulez-vous continuer avec ces informations ? (oui/non): " confirmation

    # Si l'utilisateur confirme, continuer, sinon recommencer
    if [[ "$confirmation" == "oui" || "$confirmation" == "o" ]]; then
        echo "Vous avez confirmé les informations. Le script va continuer."
        # Ajouter ici les actions à réaliser après confirmation
        # Par exemple, configurer l'interface réseau et appliquer les paramètres

        # Exemple d'ajout des configurations (à ajuster en fonction de votre besoin)
        echo "Configuration de l'interface réseau $selected_interface..."
        sudo ip addr add $ip_address/$subnet_mask dev $selected_interface
        sudo ip route add default via $gateway
        echo "DNS primaires : $dns_primary" | sudo tee /etc/resolv.conf
        echo "DNS secondaires : $dns_secondary" | sudo tee -a /etc/resolv.conf
        echo "Configuration terminée."

    else
        echo "Les informations ont été rejetées. Veuillez recommencer."
        # Recommencer le script
        config_network
    fi
}

# Démarrer le script
config_network


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