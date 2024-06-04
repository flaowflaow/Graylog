### Génération des certficats SSL et configuration HTTPS

##### DEMANDE DES VARIABLES PERSONNALISÉES #####
echo "Veuillez fournir les informations suivantes :"
read -p "Adresse IP: " ip_address
read -p "Votre domaine (ex: yourdomain.local): "  domain
read -p "hostname : "  hostname
read -p "Pays : "  country
read -p "Région : " state
read -p "Ville : " city
read -p "Lieu : " location
fqdn="$hostname.$domain"
# Création du fichier de configuration pour openssl
mkdir ssl
chmod ssl 744 ssl
cat <<EOF > ./ssl/openssl-graylog.cnf
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no
[req_distinguished_name]
C = $country
ST = $state
L = $city
O = $location
OU = Supervision
CN = $fqdn
[v3_req]
keyUsage = digitalSignature, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
IP.1 = $ip_address 
DNS.1 = $fqdn # (nom dns de mon serveur on peut aussi l'ajouter dans le fichier /etc/hosts)   
EOF
# Génération du certificat au format x.509 et la clé privé au format PKSC#5 
openssl req -x509 -days 365 -nodes -newkey rsa:2048 -config ./ssl/openssl-graylog.cnf -keyout ./ssl/pkcs5-privatekey.pem -out ./ssl/graylog-certificate.pem
# Conversion de la clé privée en PKCS#8 (sans mot de passe)
openssl pkcs8 -in ./ssl/pkcs5-privatekey.pem -topk8 -nocrypt -out ./ssl/graylog-privatekey.pem
chmod 644 ssl/*
