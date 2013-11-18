#!/bin/sh
# 入力
echo -n "input aws_access_key_id > "
read KEY_ID
echo -n "input aws_secret_access_key > "
read ACCESS_KEY
echo -n "input region > "
read REASION

$KEY_ID =~ s/[\r\n]//g;
$ACCESS_KEY =~ s/[\r\n]//g;
$REASION =~ s/[\r\n]//g;

wget http://peak.telecommunity.com/dist/ez_setup.py
python ez_setup.py
easy_install pip
pip install awscli
mkdir ~/.aws
touch ~/.aws/config
printf "[default]\n" > ~/.aws/config
printf "aws_access_key_id = %s\n"$KEY_ID >> ~/.aws/config
printf "aws_secret_access_key = %s\n"$ACCESS_KEY >> ~/.aws/config
printf "region = %s\n"$REASION >> ~/.aws/config
aws ec2 describe-instances --dry-run

# jq インストール
yum install -y jq

# rubyインストール
yum install -y ruby ruby-devel ruby-docs
ruby -v

# gemsインストール
wget http://rubyforge.org/frs/download.php/76729/rubygems-1.8.25.tgz
tar zxvf rubygems-1.8.25.tgz
cd rubygems-1.8.25
ruby setup.rb
gem -v

# rubyライブラリインストール
gem install json

# test実行
aws ec2 describe-instances