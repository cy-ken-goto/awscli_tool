#!/bin/env ruby
require 'aws_include.rb'

# コマンドライン引数受取
require 'optparse'

# デフォルト値を設定する
config = {
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
        opts.on('-s size',
                '--size size',
                "変更後のEBS容量を指定(GB)") {
            |v| config[:size] = v
        }
        opts.on('-u user',
                '--user user',
                "対象サーバへのログインユーザを指定（デフォルト値：#{config[:user]}）※ユーザ指定する場合sudo可能であること") {
            |v| config[:arg3] = v
        }
        opts.on('-k key',
                '--key key',
                "対象サーバへのログイン鍵を指定（デフォルト値：なし）") {
            |v| config[:key] = v
        }

        opts.parse!(ARGV)

    rescue => e
        puts opts.help
        puts
        puts e.message
        exit(1)
    end
end

# 引数受取
key_flg = false
root_user_flg = true
if !config[:instance_id].nil? then
    input_id = config[:instance_id]
else
    input_id = input("EC2インスタンスのidを入力して下さい : ")
end
if !config[:size].nil? then
    input_size = config[:size]
else
    input_size = input("変更後のVolumeのサイズを入力して下さい(GB) : ")
end
input_user_name = config[:user]
if input_user_name != "root"
    root_user_flg = false
end
if !config[:key].nil? then
    key_file = config[:key]
    key_flg = true
end

# インスタンスがStop中の場合Startする
if get_instance_state(input_id) != "running" then
    start_instance(input_id)
end

# インスタンスの情報取得
instance_data = get_instance_data(input_id)

# sshコマンドの実行準備
ssh_str = "ssh -o \"StrictHostKeyChecking no\" "
if key_flg then
    ssh_str += "-i " + key_file + " "
end
ssh_str += input_user_name + "@" + instance_data["private_ip"] + " "
if !root_user_flg then
    ssh_str += "sudo "
end

# 現在のvolumeサイズと比較チェック
volume_data = get_volume_id(instance_data["volume_id"])
print("現在のVolumeSize : " + volume_data["size"].to_s + "GB\n")
if input_size.to_i <= volume_data["size"] then
    print("サイズを下げることは出来ません\n")
    exit(1)
end

# チェック用ファイル作成
exec_command(ssh_str + "touch ssh_chk.txt");

# dfコマンドで対象サーバのルートデバイスを取得
device_pos = exec_command(ssh_str + "df -x tmpfs | grep / | cut -d' ' -f1")

# Instanceストップ
stop_instance(input_id)

description = "ec2InstanceVolumeUp"
new_snapshot_id = create_snapshot(instance_data["volume_id"], input_id,"ec2InstanceVolumeUp")
puts "Snapshot作成完了 : " + new_snapshot_id

new_volume_id = create_volume(new_snapshot_id, input_size, instance_data["availability_zone"])
puts "新規Volume作成完了 : " + new_volume_id

detach_volume(instance_data["volume_id"])
puts "旧Volume detach完了 : " + instance_data["volume_id"]

attach_volume(new_volume_id, input_id, instance_data["device_name"])
puts "新規Volume attach完了 : " + new_volume_id

# Instanceスタート
start_instance(input_id)

old_volume_id = instance_data["volume_id"]

# 再起動しているためもう一度インスタンス情報
instance_data = get_instance_data(input_id)
ssh_str = "ssh -o \"StrictHostKeyChecking no\" "
if key_flg then
    ssh_str += "-i " + key_file + " "
end
ssh_str += input_user_name + "@" + instance_data["private_ip"] + " "
if !root_user_flg then
    ssh_str += "sudo "
end

# リサイズ
exec_command(ssh_str + "resize2fs " + device_pos)

# ファイル存在チェック
response = exec_command(ssh_str + "cat ssh_chk.txt")
if response != "cat: ssh_chk.txt: No such file or directory" then
    exec_command(ssh_str + "rm -f ssh_chk.txt")
    if delete_volume(old_volume_id) then
        puts "旧Volume 削除完了 : " + instance_data["volume_id"]
    end

    puts "Finish!!"
    exit(0)
else
    puts "Error!!"
    exit(1)
end

