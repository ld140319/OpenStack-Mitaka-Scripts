#!/bin/bash -ex
#
# RABBIT_PASS=
# ADMIN_PASS=

source config.cfg
source functions.sh

# echocolor "Configuring net forward for all VMs"
# sleep 5
# echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
# echo "net.ipv4.conf.all.rp_filter=0" >> /etc/sysctl.conf
# echo "net.ipv4.conf.default.rp_filter=0" >> /etc/sysctl.conf
# sysctl -p

echocolor "Create DB for NEUTRON "
sleep 5
cat << EOF | mysql -uroot -p$MYSQL_PASS
CREATE DATABASE neutron;
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$NEUTRON_DBPASS';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$NEUTRON_DBPASS';
FLUSH PRIVILEGES;
EOF


echocolor "Create  user, endpoint for NEUTRON"
sleep 5

openstack user create neutron --domain default --password $NEUTRON_PASS

openstack role add --project service --user neutron admin

openstack service create --name neutron \
    --description "OpenStack Networking" network

openstack endpoint create --region RegionOne \
    network public http://$CTL_MGNT_IP:9696

openstack endpoint create --region RegionOne \
    network internal http://$CTL_MGNT_IP:9696

openstack endpoint create --region RegionOne \
    network admin http://$CTL_MGNT_IP:9696

# SERVICE_TENANT_ID=`keystone tenant-get service | awk '$2~/^id/{print $4}'`

echocolor "Install NEUTRON node - Using Linux Bridge"
sleep 5
yum -y install openstack-neutron openstack-neutron-ml2 \
  openstack-neutron-linuxbridge python-neutronclient ebtables ipset
  

######## Backup configuration NEUTRON.CONF ##################"
echocolor "Config NEUTRON"
sleep 5

#
neutron_ctl=/etc/neutron/neutron.conf
test -f $neutron_ctl.orig || cp $neutron_ctl $neutron_ctl.orig

## [DEFAULT] section
ops_edit $neutron_ctl DEFAULT core_plugin ml2
ops_edit $neutron_ctl DEFAULT service_plugins
ops_edit $neutron_ctl DEFAULT rpc_backend rabbit
ops_edit $neutron_ctl DEFAULT auth_strategy keystone
ops_edit $neutron_ctl DEFAULT notify_nova_on_port_status_changes True
ops_edit $neutron_ctl DEFAULT notify_nova_on_port_data_changes True
ops_edit $neutron_ctl DEFAULT nova_url http://$CTL_MGNT_IP:8774/v2
ops_edit $neutron_ctl DEFAULT verbose True
ops_edit $neutron_ctl DEFAULT allow_overlapping_ips True

## [database] section
ops_edit $neutron_ctl database connection mysql+pymysql://neutron:$NEUTRON_DBPASS@$CTL_MGNT_IP/neutron

## [keystone_authtoken] section
ops_edit $neutron_ctl keystone_authtoken auth_uri http://$CTL_MGNT_IP:5000
ops_edit $neutron_ctl keystone_authtoken auth_url http://$CTL_MGNT_IP:35357
ops_edit $neutron_ctl keystone_authtoken auth_plugin password
ops_edit $neutron_ctl keystone_authtoken project_domain_id default
ops_edit $neutron_ctl keystone_authtoken user_domain_id default
ops_edit $neutron_ctl keystone_authtoken project_name service
ops_edit $neutron_ctl keystone_authtoken username neutron
ops_edit $neutron_ctl keystone_authtoken password $NEUTRON_PASS

## [oslo_messaging_rabbit] section
ops_edit $neutron_ctl oslo_messaging_rabbit rabbit_host $CTL_MGNT_IP
ops_edit $neutron_ctl oslo_messaging_rabbit rabbit_userid openstack
ops_edit $neutron_ctl oslo_messaging_rabbit rabbit_password $RABBIT_PASS

## [nova] section
ops_edit $neutron_ctl nova auth_url http://$CTL_MGNT_IP:35357
ops_edit $neutron_ctl nova auth_plugin password
ops_edit $neutron_ctl nova project_domain_id default
ops_edit $neutron_ctl nova user_domain_id default
ops_edit $neutron_ctl nova region_name RegionOne
ops_edit $neutron_ctl nova project_name service
ops_edit $neutron_ctl nova username nova
ops_edit $neutron_ctl nova password $NOVA_PASS

## [oslo_concurrency] section
ops_edit $neutron_ctl oslo_concurrency lock_path /var/lib/neutron/tmp

####################### Backup configuration of ML2 ################################
echocolor "Configuring ML2"
sleep 7

ml2_clt=/etc/neutron/plugins/ml2/ml2_conf.ini
test -f $ml2_clt.orig || cp $ml2_clt $ml2_clt.orig

## [ml2] section
ops_edit $ml2_clt ml2 type_drivers flat,vlan
ops_edit $ml2_clt ml2 tenant_network_types
ops_edit $ml2_clt ml2 mechanism_drivers linuxbridge
ops_edit $ml2_clt ml2 extension_drivers port_security

## [ml2_type_flat] section
ops_edit $ml2_clt ml2_type_flat flat_networks public

## [securitygroup] section
ops_edit $ml2_clt securitygroup enable_ipset True

####################### Backup configuration of ML2 ################################
echocolor "Configuring linuxbridge_agent"
sleep 5
lbfile=/etc/neutron/plugins/ml2/linuxbridge_agent.ini
test -f $lbfile.orig || cp $lbfile $lbfile.orig

# [linux_bridge] section
ops_edit $lbfile linux_bridge physical_interface_mappings public:eth1

# [vxlan] section
ops_edit $lbfile vxlan enable_vxlan False

# [agent] section
ops_edit $lbfile agent prevent_arp_spoofing True

# [securitygroup] section
ops_edit $lbfile securitygroup enable_security_group True
ops_edit $lbfile securitygroup firewall_driver neutron.agent.linux.iptables_firewall.IptablesFirewallDriver

####################### Configuring DHCP AGENT ################################
echocolor "Configuring DHCP AGENT"
sleep 7
#
netdhcp=/etc/neutron/dhcp_agent.ini
test -f $netdhcp.orig || cp $netdhcp $netdhcp.orig

## [DEFAULT] section
ops_edit $netdhcp DEFAULT interface_driver neutron.agent.linux.interface.BridgeInterfaceDriver
ops_edit $netdhcp DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
ops_edit $netdhcp DEFAULT enable_isolated_metadata True

####################### Configuring METADATA AGENT ################################
echocolor "Configuring METADATA AGENT"
sleep 7
netmetadata=/etc/neutron/metadata_agent.ini
test -f $netmetadata.orig || cp $netmetadata $netmetadata.orig

## [DEFAULT]
ops_edit $netmetadata DEFAULT auth_uri http://$CTL_MGNT_IP:5000
ops_edit $netmetadata DEFAULT auth_url http://$CTL_MGNT_IP:35357
ops_edit $netmetadata DEFAULT auth_region  RegionOne
ops_edit $netmetadata DEFAULT auth_plugin  password
ops_edit $netmetadata DEFAULT project_domain_id  default
ops_edit $netmetadata DEFAULT user_domain_id  default
ops_edit $netmetadata DEFAULT project_name  service
ops_edit $netmetadata DEFAULT username  neutron
ops_edit $netmetadata DEFAULT password  $NEUTRON_PASS
ops_edit $netmetadata DEFAULT nova_metadata_ip $CTL_MGNT_IP
ops_edit $netmetadata DEFAULT metadata_proxy_shared_secret $METADATA_SECRET
ops_edit $netmetadata DEFAULT verbose True


echocolor "Create a symbolic link"
sleep 3
ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini

echocolor "Setup db"
sleep 3
su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron
  

echocolor "Restarting NEUTRON service"
sleep 3
systemctl enable neutron-server.service \
  neutron-linuxbridge-agent.service neutron-dhcp-agent.service \
  neutron-metadata-agent.service
  
systemctl start neutron-server.service \
  neutron-linuxbridge-agent.service neutron-dhcp-agent.service \
  neutron-metadata-agent.service

systemctl restart neutron-server.service \
  neutron-linuxbridge-agent.service neutron-dhcp-agent.service \
  neutron-metadata-agent.service
  
echocolor "Check service Neutron"
sleep 90
neutron agent-list
echocolor "Finished install NEUTRON on CONTROLLER"
