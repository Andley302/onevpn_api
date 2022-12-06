#!/bin/bash
install_ovpn() {
		if readlink /proc/$$/exe | grep -qs "dash"; then
			echo "Este script precisa ser executado com bash, não sh"
			exit 1
		fi
		[[ "$EUID" -ne 0 ]] && {
			clear
			echo "Execute como root!"
			exit 2
		}
		[[ ! -e /dev/net/tun ]] && {
			echo -e "TUN TAP NAO DISPONIVEL"
			sleep 2
			exit 3
		}
		if grep -qs "CentOS release 5" "/etc/redhat-release"; then
			echo "O CentOS 5 é muito antigo e não é suportado"
			exit 4
		fi
		if [[ -e /etc/debian_version ]]; then
			OS=debian
			GROUPNAME=nogroup
			RCLOCAL='/etc/rc.local'
		elif [[ -e /etc/centos-release || -e /etc/redhat-release ]]; then
			OS=centos
			GROUPNAME=nobody
			RCLOCAL='/etc/rc.d/rc.local'
		else
			echo -e "SISTEMA NAO SUPORTADO"
			exit 5
		fi
		newclient() {
			# gerar client.ovpn
			cp /etc/openvpn/client-common.txt ~/$1.ovpn
			echo "<ca>" >>~/$1.ovpn
			cat /etc/openvpn/easy-rsa/pki/ca.crt >>~/$1.ovpn
			echo "</ca>" >>~/$1.ovpn
			echo "<cert>" >>~/$1.ovpn
			cat /etc/openvpn/easy-rsa/pki/issued/$1.crt >>~/$1.ovpn
			echo "</cert>" >>~/$1.ovpn
			echo "<key>" >>~/$1.ovpn
			cat /etc/openvpn/easy-rsa/pki/private/$1.key >>~/$1.ovpn
			echo "</key>" >>~/$1.ovpn
			echo "<tls-auth>" >>~/$1.ovpn
			cat /etc/openvpn/ta.key >>~/$1.ovpn
			echo "</tls-auth>" >>~/$1.ovpn
		}
		IP1=$(ip addr | grep 'inet' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -o -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
		IP2=$(wget -4qO- "http://whatismyip.akamai.com/")
		[[ "$IP1" = "" ]] && {
			IP1=$(hostname -I | cut -d' ' -f1)
		}
		[[ "$IP1" != "$IP2" ]] && {
			IP="$IP1"
		} || {
			IP="$IP2"
		}
		[[ $(netstat -nplt | grep -wc 'openvpn') != '0' ]] && {
			while :; do
				clear

				opnp=$(cat /etc/openvpn/server.conf | grep "port" | awk {'print $2'})
				[[ -d /var/www/html/openvpn ]] && {
					ovpnweb=$(echo -e "◉ ")
				} || {
					ovpnweb=$(echo -e "○ ")
				}
				if grep "duplicate-cn" /etc/openvpn/server.conf >/dev/null; then
					mult=$(echo -e "◉ ")
				else
					mult=$(echo -e "○ ")
				fi
				echo -e "          GERENCIAR OPENVPN           "
				echo ""
				echo -e "PORTA: $opnp"
				echo ""
				echo -e "• ALTERAR PORTA"
				echo -e "• REMOVER OPENVPN"
				echo -e "• OVPN VIA LINK $ovpnweb"
				echo -e "• MULTILOGIN OVPN $mult"
				echo -e "• ALTERAR HOST DNS"
				echo -e "• VOLTAR"
				echo ""
				echo -ne "OQUE DESEJA FAZER ?? "
				read option
				case $option in
				1)
					clear
					echo -e "         ALTERAR PORTA OPENVPN         "
					echo ""
					echo -e "PORTA EM USO: $opnp"
					echo ""
					echo -ne "QUAL PORTA DESEJA UTILIZAR ? "
					read porta
					[[ -z "$porta" ]] && {
						echo ""
						echo -e "Porta invalida!"
						sleep 3
						echo "Finalizado!";
					}
					verif_ptrs
					echo ""
					echo -e "ALTERANDO A PORTA OPENVPN!"
					echo ""
					fun_opn() {
						var_ptovpn=$(sed -n '1 p' /etc/openvpn/server.conf)
						sed -i "s/\b$var_ptovpn\b/port $porta/g" /etc/openvpn/server.conf
						sleep 1
						var_ptovpn2=$(sed -n '7 p' /etc/openvpn/client-common.txt | awk {'print $NF'})
						sed -i "s/\b$var_ptovpn2/\b$porta/g" /etc/openvpn/client-common.txt
						sleep 1
						service openvpn restart
					}
					fun_bar 'fun_opn'
					echo ""
					echo -e "PORTA ALTERADA COM SUCESSO!"
					sleep 2
					echo "Finalizado!";
					;;
				2)
					echo ""
					echo -ne "DESEJA REMOVER O OPENVPN ? [s/n]: "
					read REMOVE
					[[ "$REMOVE" = 's' ]] && {
						rmv_open() {
							PORT=$(grep '^port ' /etc/openvpn/server.conf | cut -d " " -f 2)
							PROTOCOL=$(grep '^proto ' /etc/openvpn/server.conf | cut -d " " -f 2)
							IP=$(grep 'iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j SNAT --to ' $RCLOCAL | cut -d " " -f 11)
							if pgrep firewalld; then
								firewall-cmd --zone=public --remove-port=$PORT/$PROTOCOL
								firewall-cmd --zone=trusted --remove-source=10.8.0.0/24
								firewall-cmd --permanent --zone=public --remove-port=$PORT/$PROTOCOL
								firewall-cmd --permanent --zone=trusted --remove-source=10.8.0.0/24
							fi
							if iptables -L -n | grep -qE 'REJECT|DROP|ACCEPT'; then
								iptables -D INPUT -p $PROTOCOL --dport $PORT -j ACCEPT
								iptables -D FORWARD -s 10.8.0.0/24 -j ACCEPT
								iptables -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
								sed -i "/iptables -I INPUT -p $PROTOCOL --dport $PORT -j ACCEPT/d" $RCLOCAL
								sed -i "/iptables -I FORWARD -s 10.8.0.0\/24 -j ACCEPT/d" $RCLOCAL
								sed -i "/iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT/d" $RCLOCAL
							fi
							iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -j SNAT --to $IP
							sed -i '/iptables -t nat -A POSTROUTING -s 10.8.0.0\/24 -j SNAT --to /d' $RCLOCAL
							if hash sestatus 2>/dev/null; then
								if sestatus | grep "Current mode" | grep -qs "enforcing"; then
									if [[ "$PORT" != '1194' || "$PROTOCOL" = 'tcp' ]]; then
										semanage port -d -t openvpn_port_t -p $PROTOCOL $PORT
									fi
								fi
							fi
							[[ "$OS" = 'debian' ]] && {
								apt-get remove --purge -y openvpn openvpn-blacklist
								apt-get autoremove openvpn -y
								apt-get autoremove -y
							} || {
								yum remove openvpn -y
							}
							rm -rf /etc/openvpn
							rm -rf /usr/share/doc/openvpn*
						}
						echo ""
						echo -e "REMOVENDO O OPENVPN!"
						echo ""
						fun_bar 'rmv_open'
						echo ""
						echo -e "OPENVPN REMOVIDO COM SUCESSO!"
						sleep 2
						echo "Finalizado!";
					} || {
						echo ""
						echo -e "Retornando..."
						sleep 2
						echo "Finalizado!";
					}
					;;
				3)
					[[ -d /var/www/html/openvpn ]] && {
						clear
						fun_spcr() {
							apt-get remove apache2 -y
							apt-get autoremove -y
							rm -rf /var/www/html/openvpn
						}
						function aguarde() {
							helice() {
								fun_spcr >/dev/null 2>&1 &
								tput civis
								while [ -d /proc/$! ]; do
									for i in / - \\ \|; do
										sleep .1
										echo -ne "$i"
									done
								done
								tput cnorm
							}
							echo -ne "DESATIVANDO... "
							helice
							echo -e "Ok"
						}
						aguarde
						sleep 2
						echo "Script Finalizado!";
					} || {
						clear
						fun_apchon() {
							apt-get install apache2 zip -y
							#sed -i "s/Listen 80/Listen 81/g" /etc/apache2/ports.conf
							service apache2 restart
							[[ ! -d /var/www/html ]] && {
								mkdir /var/www/html
							}
							[[ ! -d /var/www/html/openvpn ]] && {
								mkdir /var/www/html/openvpn
							}
							touch /var/www/html/openvpn/index.html
							chmod -R 755 /var/www
							/etc/init.d/apache2 restart
						}
						function aguarde2() {
							helice() {
								fun_apchon >/dev/null 2>&1 &
								tput civis
								while [ -d /proc/$! ]; do
									for i in / - \\ \|; do
										sleep .1
										echo -ne "$i"
									done
								done
								tput cnorm
							}
							echo -ne "ATIVANDO... "
							helice
							echo -e "Ok"
						}
						aguarde2
						echo "Script Finalizado!";
					}
					;;
				4)
					if grep "duplicate-cn" /etc/openvpn/server.conf >/dev/null; then
						clear
						fun_multon() {
							sed -i '/duplicate-cn/d' /etc/openvpn/server.conf
							sleep 1.5s
							service openvpn restart >/dev/null
							sleep 2
						}
						fun_spinmult() {
							helice() {
								fun_multon >/dev/null 2>&1 &
								tput civis
								while [ -d /proc/$! ]; do
									for i in / - \\ \|; do
										sleep .1
										echo -ne "$i"
									done
								done
								tput cnorm
							}
							echo ""
							echo -ne "BLOQUEANDO MULTILOGIN... "
							helice
							echo -e "Ok"
						}
						fun_spinmult
						sleep 1
						echo "Script Finalizado!";
					else
						clear
						fun_multoff() {
							grep -v "^duplicate-cn" /etc/openvpn/server.conf >/tmp/tmpass && mv /tmp/tmpass /etc/openvpn/server.conf
							echo "duplicate-cn" >>/etc/openvpn/server.conf
							sleep 1.5s
							service openvpn restart >/dev/null
						}
						fun_spinmult2() {
							helice() {
								fun_multoff >/dev/null 2>&1 &
								tput civis
								while [ -d /proc/$! ]; do
									for i in / - \\ \|; do
										sleep .1
										echo -ne "$i"
									done
								done
								tput cnorm
							}
							echo ""
							echo -ne "PERMITINDO MULTILOGIN... "
							helice
							echo -e "Ok"
						}
						fun_spinmult2
						sleep 1
						echo "Script Finalizado!";
					fi
					;;
				5)
					clear
					echo -e "         ALTERAR HOST DNS           "
					echo ""
					echo -e "• ADICIONAR HOST DNS"
					echo -e " • REMOVER HOST DNS"
					echo -e " • EDITAR MANUALMENTE"
					echo -e " • VOLTAR"
					echo ""
					echo -ne "OQUE DESEJA FAZER ?? "
					read resp
					[[ -z "$resp" ]] && {
						echo ""
						echo -e "Opcao invalida!"
						sleep 3
						echo "Script Finalizado!";
					}
					if [[ "$resp" = '1' ]]; then
						clear
						echo -e "            Adicionar Host DNS            "
						echo ""
						echo -e "Lista dos hosts atuais: "
						echo ""
						i=0
						for _host in $(grep -w "127.0.0.1" /etc/hosts | grep -v "localhost" | cut -d' ' -f2); do
							echo -e "$_host"
						done
						echo ""
						echo -ne "Digite o host a ser adicionado : "
						read host
						if [[ -z $host ]]; then
							echo ""
							echo -e "        Campo Vazio ou invalido !       "
							sleep 2
							echo "Script Finalizado!";
						fi
						if [[ "$(grep -w "$host" /etc/hosts | wc -l)" -gt "0" ]]; then
							echo -e "    Esse host ja está adicionado  !    "
							sleep 2
							echo "Script Finalizado!";
						fi
						sed -i "3i\127.0.0.1 $host" /etc/hosts
						echo ""
						echo -e "      Host adicionado com sucesso !      "
						sleep 2
						echo "Script Finalizado!";
					elif [[ "$resp" = '2' ]]; then
						clear
						echo -e "            Remover Host DNS            "
						echo ""
						echo -e "Lista dos hosts atuais: "
						echo ""
						i=0
						for _host in $(grep -w "127.0.0.1" /etc/hosts | grep -v "localhost" | cut -d' ' -f2); do
							i=$(expr $i + 1)
							oP+=$i
							[[ $i == [1-9] ]] && oP+=" 0$i" && i=0$i
							oP+=":$_host\n"
							echo -e "[$i] - $_host"
						done
						echo ""
						echo -ne "Selecione o host a ser removido [1-$i]: "
						read option
						if [[ -z $option ]]; then
							echo ""
							echo -e "          Opcao invalida  !        "
							sleep 2
							echo "Script Finalizado!";
						fi
						host=$(echo -e "$oP" | grep -E "\b$option\b" | cut -d: -f2)
						hst=$(grep -v "127.0.0.1 $host" /etc/hosts)
						echo "$hst" >/etc/hosts
						echo ""
						echo -e "      Host removido com sucesso !      "
						sleep 2
						echo "Script Finalizado!";
					elif [[ "$resp" = '3' ]]; then
						echo -e "ALTERANDO ARQUIVO /etc/hosts"
						echo -e "ATENCAO!"
						echo -e "PARA SALVAR USE AS TECLAS ctrl x y"
						sleep 4
						clear
						nano /etc/hosts
						echo -e "ALTERADO COM SUCESSO!"
						sleep 3
						echo "Script Finalizado!";
					elif [[ "$resp" = '0' ]]; then
						echo ""
						echo -e "Retornando..."
						sleep 2
						echo "Finalizado!";
					else
						echo ""
						echo -e "Opcao invalida !"
						sleep 2
						echo "Script Finalizado!";
					fi
					;;
				0)
					echo "Finalizado!";
					;;
				*)
					echo ""
					echo -e "Opcao invalida !"
					sleep 2
					echo "Script Finalizado!";
					;;
				esac
			done
		} || {
			clear
			echo -e "              INSTALADOR OPENVPN               "
			echo ""
			echo -e "RESPONDA AS QUESTOES PARA INICIAR A INSTALACAO"
			echo ""
			echo -ne "PARA CONTINUAR CONFIRME SEU IP: "
			read -e -i $IP IP
			[[ -z "$IP" ]] && {
				echo ""
				echo -e "IP invalido!"
				sleep 3
				echo "Finalizado!";
			}
			echo ""
			read -p "$(echo -e "QUAL PORTA DESEJA UTILIZAR? ")" -e -i 1194 porta
			[[ -z "$porta" ]] && {
				echo ""
				echo -e "Porta invalida!"
				sleep 2
				echo "Finalizado!";
			}
			echo ""
			echo -e "VERIFICANDO PORTA..."
			verif_ptrs $porta
			echo ""
			echo -e "1 - Sistema"
			echo -e "2 - Google (Recomendado)"
			echo -e "3 - OpenDNS"
			echo -e "4 - Cloudflare"
			echo -e "5 - Hurricane Electric"
			echo -e "6 - Verisign"
			echo -e "7 - DNS Performace"
			echo ""
			read -p "$(echo -e "QUAL DNS DESEJA UTILIZAR? ")" -e -i 2 DNS
			echo ""
			echo -e "1 - UDP"
			echo -e "2 - TCP (Recomendado)"
			echo ""
			read -p "$(echo -e "QUAL PROTOCOLO DESEJA UTILIZAR NO OPENVPN? ")" -e -i 2 resp
			if [[ "$resp" = '1' ]]; then
				PROTOCOL=udp
			elif [[ "$resp" = '2' ]]; then
				PROTOCOL=tcp
			else
				PROTOCOL=tcp
			fi
			echo ""
			[[ "$OS" = 'debian' ]] && {
				echo -e "ATUALIZANDO O SISTEMA"
				echo ""
				fun_attos() {
					apt-get update-y
				}
				fun_bar 'fun_attos'
				echo ""
				echo -e "INSTALANDO DEPENDENCIAS"
				echo ""
				fun_instdep() {
					apt-get install openvpn iptables openssl ca-certificates -y
					apt-get install zip -y
				}
				fun_bar 'fun_instdep'
			} || {
				fun_bar 'yum install epel-release -y'
				fun_bar 'yum install openvpn iptables openssl wget ca-certificates -y'
			}
			[[ -d /etc/openvpn/easy-rsa/ ]] && {
				rm -rf /etc/openvpn/easy-rsa/
			}
			# Adquirindo easy-rsa
			echo ""
			fun_dep() {
				wget -O ~/EasyRSA-3.0.1.tgz "https://github.com/OpenVPN/easy-rsa/releases/download/3.0.1/EasyRSA-3.0.1.tgz"
				[[ ! -e $HOME/EasyRSA-3.0.1.tgz ]] && {
					#alternate easy install
					wget -O ~/EasyRSA-3.0.1.tgz "https://raw.githubusercontent.com/AAAAAEXQOSyIpN2JZ0ehUQ/SSHPLUS-MANAGER-FREE/master/Install/EasyRSA-3.0.1.tgz"
				}
				tar xzf ~/EasyRSA-3.0.1.tgz -C ~/
				mv ~/EasyRSA-3.0.1/ /etc/openvpn/
				mv /etc/openvpn/EasyRSA-3.0.1/ /etc/openvpn/easy-rsa/
				chown -R root:root /etc/openvpn/easy-rsa/
				rm -rf ~/EasyRSA-3.0.1.tgz
				cd /etc/openvpn/easy-rsa/
				./easyrsa init-pki
				./easyrsa --batch build-ca nopass
				./easyrsa gen-dh
				./easyrsa build-server-full server nopass
				./easyrsa build-client-full onehostapps nopass
				./easyrsa gen-crl
				cp pki/ca.crt pki/private/ca.key pki/dh.pem pki/issued/server.crt pki/private/server.key /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn
				chown nobody:$GROUPNAME /etc/openvpn/crl.pem
				openvpn --genkey --secret /etc/openvpn/ta.key
				# Generando server.conf
				echo "port $porta
proto $PROTOCOL
dev tun
sndbuf 0
rcvbuf 0
ca ca.crt
cert server.crt
key server.key
dh dh.pem
tls-auth ta.key 0
topology subnet
server 10.8.0.0 255.255.0.0
ifconfig-pool-persist ipp.txt" >/etc/openvpn/server.conf
				echo 'push "redirect-gateway def1 bypass-dhcp"' >>/etc/openvpn/server.conf
				# DNS
				case $DNS in
				1)
					# Obtain the resolvers from resolv.conf and use them for OpenVPN
					grep -v '#' /etc/resolv.conf | grep 'nameserver' | grep -E -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | while read line; do
						echo "push \"dhcp-option DNS $line\"" >>/etc/openvpn/server.conf
					done
					;;
				2)
					echo 'push "dhcp-option DNS 8.8.8.8"' >>/etc/openvpn/server.conf
					echo 'push "dhcp-option DNS 8.8.4.4"' >>/etc/openvpn/server.conf
					;;
				3)
					echo 'push "dhcp-option DNS 208.67.222.222"' >>/etc/openvpn/server.conf
					echo 'push "dhcp-option DNS 208.67.220.220"' >>/etc/openvpn/server.conf
					;;
				4)
					echo 'push "dhcp-option DNS 1.1.1.1"' >>/etc/openvpn/server.conf
					echo 'push "dhcp-option DNS 1.0.0.1"' >>/etc/openvpn/server.conf
					;;
				5)
					echo 'push "dhcp-option DNS 74.82.42.42"' >>/etc/openvpn/server.conf
					;;
				6)
					echo 'push "dhcp-option DNS 64.6.64.6"' >>/etc/openvpn/server.conf
					echo 'push "dhcp-option DNS 64.6.65.6"' >>/etc/openvpn/server.conf
					;;
				7)
					echo 'push "dhcp-option DNS 189.38.95.95"' >>/etc/openvpn/server.conf
					echo 'push "dhcp-option DNS 216.146.36.36"' >>/etc/openvpn/server.conf
					;;
				esac
				echo "keepalive 10 120
float
cipher AES-256-CBC
comp-lzo yes
user nobody
group $GROUPNAME
persist-key
persist-tun
status openvpn-status.log
management localhost 5555
verb 3
crl-verify crl.pem
client-to-client
client-cert-not-required
username-as-common-name
plugin $(find /usr -type f -name 'openvpn-plugin-auth-pam.so') login
duplicate-cn" >>/etc/openvpn/server.conf
				sed -i '/\<net.ipv4.ip_forward\>/c\net.ipv4.ip_forward=1' /etc/sysctl.conf
				if ! grep -q "\<net.ipv4.ip_forward\>" /etc/sysctl.conf; then
					echo 'net.ipv4.ip_forward=1' >>/etc/sysctl.conf
				fi
				echo 1 >/proc/sys/net/ipv4/ip_forward
				if [[ "$OS" = 'debian' && ! -e $RCLOCAL ]]; then
					echo '#!/bin/sh -e
exit 0' >$RCLOCAL
				fi
				chmod +x $RCLOCAL
				iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j SNAT --to $IP
				sed -i "1 a\iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j SNAT --to $IP" $RCLOCAL
				if pgrep firewalld; then
					firewall-cmd --zone=public --add-port=$porta/$PROTOCOL
					firewall-cmd --zone=trusted --add-source=10.8.0.0/24
					firewall-cmd --permanent --zone=public --add-port=$porta/$PROTOCOL
					firewall-cmd --permanent --zone=trusted --add-source=10.8.0.0/24
				fi
				if iptables -L -n | grep -qE 'REJECT|DROP'; then
					iptables -I INPUT -p $PROTOCOL --dport $porta -j ACCEPT
					iptables -I FORWARD -s 10.8.0.0/24 -j ACCEPT
					iptables -F
					iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
					sed -i "1 a\iptables -I INPUT -p $PROTOCOL --dport $porta -j ACCEPT" $RCLOCAL
					sed -i "1 a\iptables -I FORWARD -s 10.8.0.0/24 -j ACCEPT" $RCLOCAL
					sed -i "1 a\iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT" $RCLOCAL
				fi
				if hash sestatus 2>/dev/null; then
					if sestatus | grep "Current mode" | grep -qs "enforcing"; then
						if [[ "$porta" != '1194' || "$PROTOCOL" = 'tcp' ]]; then
							if ! hash semanage 2>/dev/null; then
								yum install policycoreutils-python -y
							fi
							semanage port -a -t openvpn_port_t -p $PROTOCOL $porta
						fi
					fi
				fi
			}
			echo -e "INSTALANDO O OPENVPN..."
			echo ""
			fun_bar 'fun_dep > /dev/null 2>&1'
			fun_ropen() {
				[[ "$OS" = 'debian' ]] && {
					if pgrep systemd-journal; then
						systemctl restart openvpn@server.service
					else
						/etc/init.d/openvpn restart
					fi
				} || {
					if pgrep systemd-journal; then
						systemctl restart openvpn@server.service
						systemctl enable openvpn@server.service
					else
						service openvpn restart
						chkconfig openvpn on
					fi
				}
			}
			echo ""
			echo -e "REINICIANDO O OPENVPN"
			echo ""
			fun_bar 'fun_ropen'
			IP2=$(wget -4qO- "http://whatismyip.akamai.com/")
			if [[ "$IP" != "$IP2" ]]; then
				IP="$IP2"
			fi
			#[[ $(grep -wc 'open.py' /etc/autostart) != '0' ]] && pt_proxy=$(grep -w 'open.py' /etc/autostart| cut -d' ' -f6) || pt_proxy=80
			cat <<-EOF >/etc/openvpn/client-common.txt
				# OVPN_ACCESS_SERVER_PROFILE=[onehostapps]
				client
				dev tun
				proto $PROTOCOL
				sndbuf 0
				rcvbuf 0
				remote 127.0.0.1 1194
				resolv-retry 5
				nobind
				persist-key
				persist-tun
				remote-cert-tls server
				cipher AES-256-CBC
				comp-lzo yes
				setenv opt block-outside-dns
				key-direction 1
				verb 3
				auth-user-pass
				keepalive 10 120
				float
			EOF
			# gerar client.ovpn
			newclient "onehostapps"
			[[ "$(netstat -nplt | grep -wc 'openvpn')" != '0' ]] && echo -e "\nOPENVPN INSTALADO COM SUCESSO" || echo -e "\nERRO ! A INSTALACAO CORROMPEU"
		}
		sed -i '$ i\echo 1 > /proc/sys/net/ipv4/ip_forward' /etc/rc.local
		sed -i '$ i\echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6' /etc/rc.local
		sed -i '$ i\iptables -A INPUT -p tcp --dport 25 -j DROP' /etc/rc.local
		sed -i '$ i\iptables -A INPUT -p tcp --dport 110 -j DROP' /etc/rc.local
		sed -i '$ i\iptables -A OUTPUT -p tcp --dport 25 -j DROP' /etc/rc.local
		sed -i '$ i\iptables -A OUTPUT -p tcp --dport 110 -j DROP' /etc/rc.local
		sed -i '$ i\iptables -A FORWARD -p tcp --dport 25 -j DROP' /etc/rc.local
		sed -i '$ i\iptables -A FORWARD -p tcp --dport 110 -j DROP' /etc/rc.local
		sleep 3
		clear;
}
#verifica portas
verif_ptrs() {
		porta=$1
		PT=$(lsof -V -i tcp -P -n | grep -v "ESTABLISHED" | grep -v "COMMAND" | grep "LISTEN")
		for pton in $(echo -e "$PT" | cut -d: -f2 | cut -d' ' -f1 | uniq); do
			svcs=$(echo -e "$PT" | grep -w "$pton" | awk '{print $1}' | uniq)
			[[ "$porta" = "$pton" ]] && {
				echo -e "Porta em uso: $svcs"
				sleep 3
				echo "Script finalizado!"
			}
		done
}

fun_bar() {
		comando[0]="$1"
		comando[1]="$2"
		(
			[[ -e $HOME/fim ]] && rm $HOME/fim
			${comando[0]} >/dev/null 2>&1
			${comando[1]} >/dev/null 2>&1
			touch $HOME/fim
		) >/dev/null 2>&1 &
		tput civis
		echo -ne "AGUARDE..."
		while true; do
			for ((i = 0; i < 18; i++)); do
				echo -ne "#"
				sleep 0.1s
			done
			[[ -e $HOME/fim ]] && rm $HOME/fim && break
			echo -e "..."
			sleep 1s
			tput cuu1
			tput dl1
			echo -ne "AGUARDE..."
		done
		echo -e " OK!"
		tput cnorm
}

#executa funcao
install_ovpn


