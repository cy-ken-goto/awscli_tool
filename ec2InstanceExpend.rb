#!/bin/env ruby
require 'aws_include.rb'

# コマンドライン引数受取
require 'optparse'

# デフォルト値を設定する
config = {
    :reboot => 'on',
    :user => 'root',
}

# 引数を解析する
OptionParser.new do |opts|
    begin
        # オプション情報を設定する
        opts = OptionParser.new
        opts.on('-i instance_id',
                '--instance-id instance_id',
                "EC2のInstance Idを指定") { 
            |v| config[:instance_id] = v 
        }
        opts.on('-n name',
                '--name name',
                "TagのName要素を指定") {
            |v| config[:name] = v
        }
        opts.on('-r reboot',
                '--reboot reboot',
                "on/off(default on) クローン元を再起動してImageを作成するか決定<offは非推奨>") {
            |v| config[:reboot] = v
        }
        opts.on('-u user',
                '--user user',
                "クローン元へのログインユーザを指定（デフォルト値：#{config[:user]}）※ユーザ指定する場合sudo可能であること") {
            |v| config[:arg3] = v
        }
        opts.on('-k key',
                '--key key',
                "クローン元へのログイン鍵を指定（デフォルト値：なし）") {
            |v| config[:key] = v
        }

        opts.parse!(ARGV)

    rescue => e
        puts opts.help
        puts
        puts e.message
        exit 1
    end
end

key_flg = false
root_user_flg = true
if !config[:instance_id].nil? then
    input_instance_id = config[:instance_id]
elsif !config[:name].nil? then
    input_instance_id = get_instance_id(config[:name])
else
    input_instance_id  = input("クローン元のEC2インスタンスのidを入力して下さい : ")
end
input_user_name = config[:user]
if input_user_name != "root"
    root_user_flg = false
end
if !config[:key].nil? then
    key_file = config[:key]
    key_flg = true
end

# クローン元を再起動するかチェック
reboot_flg = true
if config[:reboot] == "off" then
    reboot_flg = false
end

# クローン元インスタンス情報取得
instance_data = get_instance_data(input_instance_id)

# 新しいインスタンスの名前生成
new_instance_name = get_instanse_tag_new_name(instance_data["name"])

# クローン元がロードバランサーに入っているかチェック
# 入っていた場合外す
load_balancer_remove_flg = false
load_balancer_name = check_load_balancer(input_instance_id)
if load_balancer_name then
    if reboot_flg && deregister_instance_from_load_balancer(load_balancer_name, input_instance_id) then
        puts("指定したInstanceをLoad Balancer(" + load_balancer_name + ")から外しました")
        load_balancer_remove_flg = true
    end
end

# AMI作成
ami_id = create_image(input_instance_id, reboot_flg)
puts "AMI作成完了 : " + ami_id

# クローン元をロードバランサーから外した場合戻す
if load_balancer_remove_flg then
    if ! register_instance_from_load_balancer(load_balancer_name, input_instance_id) then
        exit 1
    end
    puts input_instance_id + "を" + load_balancer_name + "(elb)に追加しました"
end

# Instance生成
new_instance_id = create_instance(ami_id, instance_data, new_instance_name)
puts "新規Instance生成完了 : " + new_instance_id
# 各デーモンの起動を5秒待つ
sleep(5)

# NewInstance情報表示
new_instance_data = get_instance_data(new_instance_id)
puts "name : " + new_instance_data["name"]
puts "instance_type : " + new_instance_data["instance_type"]
puts "availability_zone : " + new_instance_data["availability_zone"]
puts "private_ip : " + new_instance_data["private_ip"]
puts "volume_id : " + new_instance_data["volume_id"]
puts "device_name : " + new_instance_data["device_name"]
puts "key_name : " + new_instance_data["key_name"]
print "security_groups : "
pp new_instance_data["security_groups"]

# sshコマンドの実行準備
ssh_str = "ssh -o \"StrictHostKeyChecking no\" "
if key_flg then
    ssh_str += "-i " + key_file + " "
end
ssh_str += input_user_name + "@" + new_instance_data["private_ip"] + " "
if !root_user_flg then
    ssh_str += "sudo "
end

# host名変更
cmd = ssh_str + "sed -e \"s/localhost.localdomain\\\|" + instance_data["name"]
cmd += "/" + new_instance_name + "/g\" /etc/hosts"
exec_command(cmd);
cmd = ssh_str + "sed -e \"s/localhost.localdomain\\\|" + instance_data["name"]
cmd += "/" + new_instance_name + "/g\" /etc/sysconfig/network"
exec_command(cmd);
cmd = ssh_str + "hostname " + new_instance_name
exec_command(cmd);

# NewInstanceリブート
reboot_instance(new_instance_id)
puts "Finish!!"
puts ""

# NewInstance情報表示
new_instance_data = get_instance_data(new_instance_id)
puts "name : " + new_instance_data["name"]
puts "instance_type : " + new_instance_data["instance_type"]
puts "availability_zone : " + new_instance_data["availability_zone"]
puts "private_ip : " + new_instance_data["private_ip"]
puts "volume_id : " + new_instance_data["volume_id"]
puts "device_name : " + new_instance_data["device_name"]
puts "key_name : " + new_instance_data["key_name"]
print "security_groups : "
pp new_instance_data["security_groups"]

