#!/bin/env ruby
require 'aws_include.rb'

# id受取
input_id = input("EC2インスタンスのidを入力して下さい : ")

if get_instance_state(input_id) != "running" then
    start_instance(input_id)
end

instance_data = get_instance_data(input_id)

input_user_name = input("対象サーバのユーザ名を指定してください(rootでない場合はsudo可能であること) : ")
root_user_flg = false
if input_user_name == "root"
    root_user_flg = true
end

input_key_flg = input("対象サーバへのsshログインで鍵指定は必要ですか？(y/n) : ")
if input_key_flg == "y" then
    key_flg = true
else
    key_flg = false
end

ssh_str = "ssh "
if key_flg then
    key_file = input("rootログイン可能な秘密鍵を絶対パスで指定して下さい : ")
    ssh_str += "-i " + key_file + " "
end
ssh_str += input_user_name + "@" + instance_data["private_ip"] + " "
if !root_user_flg then
    ssh_str += "sudo "
end

volume_data = get_volume_id(instance_data["volume_id"])

print("現在のVolumeSize : " + volume_data["size"].to_s + "GB\n")
input_size = input("変更後のVolumeのサイズを入力して下さい(GB) : ")

if input_size.to_i <= volume_data["size"] then
    print("サイズを下げることは出来ません\n")
    exit(0)
end

# チェック用ファイル作成
exec_command(ssh_str + "touch ssh_chk.txt");

# dfコマンドで対象サーバのルートデバイスを取得
device_pos = exec_command(ssh_str + "df -x tmpfs | grep / | cut -d' ' -f1")

# Instanceストップ
stop_instance(input_id)

new_snapshot_id = create_snapshot(instance_data["volume_id"])
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
instance_data = get_instance_data(input_id)
ssh_str = "ssh "
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

    if input("作成したSnapShotを削除しますか？(y/n) : ") == "y" then
        if delete_snapshot(new_snapshot_id) then
            puts new_snapshot_id + " 削除完了"
        end
    end
    if input("dettachされたVolumeを削除しますか？(y/n) : ") == "y" then
        if delete_volume(old_volume_id) then
            puts instance_data["volume_id"] + " 削除完了"
        end
    end

    puts "Finish!!"
else
    puts "Error!!"
end

