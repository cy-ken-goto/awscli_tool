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
echo '[default]' > ~/.aws/config
echo 'aws_access_key_id = '$KEY_ID >> ~/.aws/config
echo 'aws_secret_access_key = '$ACCESS_KEY >> ~/.aws/config
echo 'region = '$REASION >> ~/.aws/config
aws ec2 describe-instances --dry-run

# jq インストール
yum install -y jq

# rubyインストール
yum install -y ruby ruby-devel ruby-docs
ruby -v

# gemsインストール
wget http://rubyforge.org/frs/download.php/76729/rubygems-1.8.25.tgz
tar zxvf rubygems-1.8.25.tgz
ruby ./rubygems-1.8.25/setup.rb
gem -v

# rubyライブラリインストール
gem install json

# 各ダウンロードソース削除
rm -f ez_setup.py
rm -rf rubygems-1.8.25
rm -f rubygems-1.8.25.tgz

# test実行
aws ec2 describe-instances

echo 'Finish!'