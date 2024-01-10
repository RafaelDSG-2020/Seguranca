#!/bin/bash

IP_INTERNET="$(ip addr show enp0s3 | grep 'inet ' | cut -f2 | awk '{ print $2}' | cut -d/ -f1)"
IP_WEB_SERVER="192.168.57.4:80"

printf "IP da interface enp0s3: %s\n" "$IP_INTERNET"
printf "IP do servidor WEB: %s\n" "$IP_WEB_SERVER"

echo "Configurando a interface da rede interna (enp0s8)"
sudo ip link set enp0s8 up
sleep 0.2
sudo dhclient enp0s8

if [ $? -ne 0 ]
then
  echo "Erro ao configurar a interface enp0s8"
  exit 1
fi

sleep 0.2
echo "Configurando a interface da rede externa (enp0s9)"
sudo ip link set enp0s9 up
sleep 0.2
sudo dhclient enp0s9


if [ $? -ne 0 ]
then
  echo "Erro ao configurar a interface enp0s9"
  exit 1
fi

sleep 0.2
echo "Habilitando o encaminhamento de pacotes (ip_forward)"
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward

if [ $? -ne 0 ]
then
  echo "Erro ao habilitar o ip_forward"
  exit 1
fi

sleep 0.2
echo "########################"
echo "#                      #"
echo "#    VM DO FIREWALL    #"
echo "#                      #"
echo "########################"
sleep 0.2

#Configurar o NAT para masquerade:
echo "Configurar NAT para MASQUERADE"
sudo iptables -t nat -A POSTROUTING -o enp0s3 -j MASQUERADE

#Permitir o acesso remoto via SSH ao Firewall:
echo "Firewall SSH"

sudo iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sudo iptables -A OUTPUT -p tcp --sport 22 -m conntrack --ctstate ESTABLISHED -j ACCEPT
sleep 0.2

#Adicionar a política DROP às chains para descarte dos pacotes:
echo "DROP policy"

sudo iptables --policy INPUT DROP
sudo iptables --policy OUTPUT DROP
sudo iptables --policy FORWARD DROP

sleep 0.2

#Permitir o tráfego loopback no host do firewall (não necessário para o trabalho):
#(teste com ping para o próprio host. Ex.: ping 127.0.0.1)
echo "Firewall Loopback Ping"

sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A OUTPUT -o lo -j ACCEPT
sleep 0.2

#Permitir a realização de requisições de ping a partir do do Firewall:
#(teste com ping para o meio externo. Ex.: ping 8.8.8.8)
echo "Firewall Extern Ping"

sudo iptables -A INPUT -p icmp -m conntrack --ctstate ESTABLISHED -j ACCEPT
sudo iptables -A OUTPUT -p icmp -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sleep 0.2

#Permitir que o firewall receba requisições de ping de qualquer lugar da rede interna:
#(teste com ping para o firewall. Ex.: [do cliente] ping <ip-do-firewall>)
sleep 0.2
echo "Ping to Firewall"
sudo iptables -A INPUT -p icmp --icmp-type 8 -m conntrack --ctstate NEW,ESTABLISHED  -j ACCEPT
sudo iptables -A OUTPUT -p icmp --icmp-type 0 -m conntrack --ctstate ESTABLISHED -j ACCEPT

#Permitir que o host do firewall faça requisições DNS:
#(teste com nslookup. Ex.: nslookup www.google.com)
echo "Firewall DNS request"

sudo iptables -A OUTPUT -p udp --dport 53 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT -p udp --sport 53 -m conntrack --ctstate ESTABLISHED -j ACCEPT
sleep 0.2

#Permitir que o host do firewall faça requisições HTTP/HTTPS:
#(teste com wget. Ex.: wget si3.com.br)
echo "Firewall HTTP/HTTPS request"

sudo iptables -A OUTPUT -p tcp -m multiport --dports 80,443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT

#sudo iptables -A INPUT -m state --state ESTABLISHED -j ACCEPT
sleep 0.2

echo "########################"
echo "#                      #"
echo "#    VM DO CLIENTE     #"
echo "#                      #"
echo "########################"


#Permitir SSH por parte do cliente:
echo "Allows client SSH"
sudo iptables -A FORWARD -o enp0s8 -p tcp --dport 22 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i enp0s8 -p tcp --sport 22 -m conntrack --ctstate ESTABLISHED -j ACCEPT

#Permitir o tráfego de resposta a partir de conexões já estabelecidas:
echo "Allows related and established traffic"

echo Permitindo estabelecimento de conexão de retorno para todos as entradas
sudo iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sleep 0.2
 
#Permitir a realização de ping pela rede cliente:
echo "Client Extern Ping"
#(teste com ping para o meio externo. Ex.: ping 8.8.8.8)

sudo iptables -A FORWARD -i enp0s8 -o enp0s3 -p icmp --icmp-type 8 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sleep 0.2

#Permitir que a rede cliente faça requisições DNS:
echo "Client DNS request"
#(teste com nslookup. Ex.: nslookup www.google.com)

sudo iptables -A FORWARD -i enp0s8 -o enp0s3 -p udp --dport 53 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sleep 0.2

#Permitir que a rede cliente faça requisições HTTP/HTTPS:
#(teste com wget. Ex.: wget si3.com.br)
echo "Client HTTP/HTTPS request"

sudo iptables -A FORWARD -i enp0s8 -o enp0s3 -p tcp -m multiport --dports 80,443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sleep 0.2

#Permitir que a rede cliente faça requisições SMTP/FTP:
#(teste com telnet. Ex.: ftp ftp.dlptest.com  |  telnet smtp.gmail.com 587)
"Client SMTP/FTP request"

sudo iptables -A FORWARD -i enp0s8 -o enp0s3 -p tcp -m multiport --dports 587,25,21 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sleep 0.2

#Permitir o tráfego de resposta a partir de conexões já estabelecidas:
echo "Allows related and established traffic"

echo Permitindo estabelecimento de conexão de retorno para todos as entradas
sudo iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sleep 0.2


echo "########################"
echo "#                      #"
echo "#    VM DO WEBSERVER   #"
echo "#                      #"
echo "########################"


#Redirecionar o tráfego WEB destinado ao firewall ao webserver da organização na DMZ:
echo "Redirect Traffic"

sudo iptables -t nat -A PREROUTING -d $IP_INTERNET -p tcp -m tcp --dport 80 -j DNAT --to-destination $IP_WEB_SERVER
#sudo iptables -t nat -A PREROUTING -d 192.168.1.8 -p tcp -m tcp --dport 80 -j DNAT --to-destination 192.168.57.4:80
sleep 0.2

#A regra permite o encaminhamento de requisições HTTP e HTTPS da interface de internet para a interface da DMZ no firewall:
echo "Forward HTTP and HTTPS requests from internet to DMZ interface on firewal"

sudo iptables -A FORWARD -i enp0s3 -o enp0s9 -p tcp -m tcp -m multiport --dports 80,443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sleep 0.2

#Permite que a DMZ faça ping para um ip externo:
echo "Webserver Extern Ping"

sudo iptables -A FORWARD -i enp0s9 -o enp0s3 -p icmp --icmp-type 8 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sleep 0.2

#Permite que a DMZ faça requisição DNS para um ip externo
echo "Webservre DNS request"

sudo iptables -A FORWARD -i enp0s9 -o enp0s3 -p udp --dport 53 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT


# Permite que a dmz receba requisições http e https de rede externa
echo "Webserver HTTP/HTTPS request"

sudo iptables -A FORWARD -i enp0s9 -o enp0s3 -p tcp -m multiport --dport 80,443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sleep 0.2


echo "########################"
echo "#                      #"
echo "#     REGRAS SQUID     #"
echo "#                      #"
echo "########################"

#Permite que o Firewall redirecione requisições HTTP vindas da interface de internet para a porta 3129 do SQUID. 
echo "Redirecionando requisições HTTP vindas da interface de internet para a porta 3129 do SQUID"

sudo iptables -t nat -A PREROUTING -i enp0s8 -p tcp -m tcp --dport 80 -j REDIRECT --to-ports 3129

#Permite que o Firewall redirecione requisições HTTPS vindas da interface de internet para a porta 3130 do SQUID.
echo "Redirecionando requisições HTTPS vindas da interface de internet para a porta 3130 do SQUID"

sudo iptables -t nat -A PREROUTING -i enp0s8 -p tcp -m tcp --dport 433 -j REDIRECT --to-ports 3130
sleep 0.2

#Permite o tráfego de pacotes HTTP e HTTPS entre o Firewall e o SQUID.
echo "Configurando regras para o tráfego de pacotes HTTP e HTTPS entre o Firewall e o SQUID"
sudo iptables -A INPUT -i enp0s8 -p tcp -m tcp -m multiport --dports 3129,3130 -j ACCEPT
sudo iptables -A OUTPUT -o enp0s8 -p tcp -m tcp -m multiport --sports 3129,3130 -j ACCEPT

