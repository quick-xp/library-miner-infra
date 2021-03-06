#
# Cookbook Name:: zabbix::server
# Recipe:: default
#
# Copyright 2015, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

# Server Install
%w[
  zabbix-server-mysql
  zabbix-frontend-php
].each do |p|
  package p
end


# Install php-fpm to execute PHP code from nginx
package 'php5-fpm'
package 'php5-mysql'

service "php5-fpm" do
  action    [:enable, :start]
  supports  [:start, :restart, :reload, :stop]
end

# Zabbix Server Setting
template '/etc/default/zabbix-server' do
  source 'zabbix_server_default.erb'
  owner 'root'
  group 'root'
  mode '644'
end

template '/etc/zabbix/zabbix_server.conf' do
  source 'zabbix_server.conf.erb'
  owner 'root'
  group 'root'
  mode '644'
  variables(
    :dbhost     => node['zabbix']['server']['mysql']['dbhost'],
    :dbname     => node['zabbix']['server']['mysql']['dbname'],
    :dbuser     => node['zabbix']['server']['mysql']['dbuser'],
    :dbpassword => node['zabbix']['server']['mysql']['dbpassword']
  )
  notifies :restart, 'service[zabbix-server]', :delayed
end

# zabbix-serverの自動起動設定と起動
service 'zabbix-server' do
  supports :status => true, :start => true, :stop => true, :restart => true
  action [:start, :enable]
end

# nginx の設定
template "/etc/nginx/sites-available/zabbix" do
	source 'zabbix_nginx.erb'
	owner  'root'
	group  'root'
	mode   '0754'
  variables(
    :server_name => node['zabbix']['web']['fqdn'],
    :php_settings => node['zabbix']['web']['php']['settings'],
    :web_port => node['zabbix']['web']['port'],
    :web_dir => node['zabbix']['web_dir'],
    :fastcgi_listen => node['zabbix']['web']['php']['fastcgi_listen']
  )

	notifies :reload, 'service[nginx]'
end

#simbol link
link "/etc/nginx/sites-enabled/zabbix" do
	not_if "test -L /etc/nginx/sites-enabled/zabbix"
	to "/etc/nginx/sites-available/zabbix"
	link_type :symbolic
	notifies :reload, 'service[nginx]'
end

# PHP設定
template "/etc/php5/fpm/pool.d/www.conf" do
  source 'www.conf.erb'
  owner 'root'
  group 'root'
  mode '0666'

  notifies :restart, resources(:service => "php5-fpm"), :immediately
end


# -- mysql データベース作成 初期データ投入 --

# 実行完了用判定Directory
directory "/root/chef_install" do
	owner "root"
	group "root"
	mode 00744
	action :create
end

# 後から入れる場合は注意
#root_password = node['mysql']['server_root_password']
root_password = 'root'

# create db
bash "create zabbix db" do
  not_if { File.exists?("/root/chef_install/zabbix_db_create")}
  user "root"
  code <<-EOS
    mysql -h 127.0.0.1 -u root -p#{root_password} -e \
    "create database zabbix character set utf8 collate utf8_bin;"
    touch /root/chef_install/zabbix_db_create
  EOS
end

# create user
bash "create zabbix db user" do
  not_if { File.exists?("/root/chef_install/zabbix_db_user_create")}
  user "root"
  code <<-EOS
    mysql -h 127.0.0.1 -u root -p#{root_password} -e \
    "create user zabbix; \
    grant all on zabbix.* to zabbix@localhost; \
    flush privilegdes;"
    touch /root/chef_install/zabbix_db_user_create
  EOS
end

# create zabbix db schema
bash "create zabbix db schema" do
  not_if { File.exists?("/root/chef_install/zabbix_db_schema_create")}
  user "root"
  code <<-EOS
    gunzip /usr/share/zabbix-server-mysql/*.gz
    mysql -h 127.0.0.1 -u zabbix zabbix < /usr/share/zabbix-server-mysql/schema.sql
    mysql -h 127.0.0.1 -u zabbix zabbix < /usr/share/zabbix-server-mysql/images.sql
    mysql -h 127.0.0.1 -u zabbix zabbix < /usr/share/zabbix-server-mysql/data.sql
    touch /root/chef_install/zabbix_db_schema_create
  EOS
end
