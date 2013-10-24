require 'rubygems'
require 'json'
require 'pp'

# Instance Stateを取得
def get_instance_state(instance_id)
    result = JSON.parse(`#{"aws ec2 describe-instances --instance-ids " + instance_id}`)
    return result["Reservations"][0]["Instances"][0]["State"]["Name"]
end

# Instance グローバルIPを取得
def get_instance_data(instance_id)
    result = JSON.parse(`#{"aws ec2 describe-instances --instance-ids " + instance_id}`)
    return {
                "private_ip"=>result["Reservations"][0]["Instances"][0]["PrivateIpAddress"], 
                "availability_zone"=>result["Reservations"][0]["Instances"][0]["Placement"]["AvailabilityZone"]
            }
end

# volume idを取得
def get_volume_id(instance_id)
    result = JSON.parse(`#{"aws ec2 describe-instances --instance-ids " + instance_id}`)
    return result["Reservations"][0]["Instances"][0]["BlockDeviceMappings"][0]["Ebs"]["VolumeId"]
end

def create_snapshot(volume_id)
    result = JSON.parse(`#{"aws ec2 create-snapshot --volume-id " + volume_id}`)
    return result["SnapshotId"]
end

def create_volume(snapshot_id, size, availability_zone)
    result = JSON.parse(`#{"aws ec2 create-volume --snapshot-id " + snapshot_id + " --size " + size + " --availability-zone " + availability_zone}`)
    return result["VolumeId"]
end

# ec2インスタンスをstart
def start_instance(instance_id)
    if get_instance_state(instance_id) != "running" then
        puts "instance starting\n"
        result = JSON.parse(`#{"aws ec2 start-instances --instance-ids " + instance_id}`)
        check_pend(instance_id, "running")
    end
end

# ec2インスタンスをstop
def stop_instance(instance_id)
    if get_instance_state(instance_id) != "stopped" then
        puts "instance stopping\n"
        result = JSON.parse(`#{"aws ec2 stop-instances --instance-ids " + instance_id}`)
        check_pend(instance_id, "stopped")
    end
end

# penddingチェックメソッド
def check_pend(instance_id, check_state)
    current_state = ""
    while current_state != check_state
        puts "."
        current_state = get_instance_state(instance_id)
        sleep 3
    end
    print(current_state + "\n")
end

# id受取
print("EC2インスタンスのidを入力して下さい : ")
#input_id = STDIN.gets
input_id = 'i-650ab460'
print("対象サーバにrootログイン可能な秘密鍵を絶対パス指定して下さい : ")
#key_file = STDIN.gets
key_file = '~/.ssh/goto_key.pem'
print("変更後のVolumeのサイズを入力して下さい(GB) : ")
input_size = STDIN.gets

instance_data = get_instance_data(input_id)
ssh_str = "ssh -i " + key_file + " root@" + instance_data["private_ip"] + " "
# チェック用ファイル作成
`#{ssh_str + "touch ssh_chk.txt"}`

# dfコマンドで対象サーバのルートデバイスを取得
device_pos = `#{ssh_str + "df -x tmpfs | grep / | cut -d' ' -f1"}`

# Instanceストップ
stop_instance(input_id)

old_volume_id = get_volume_id(input_id)
puts "VolumeIdを取得 : " + old_volume_id
new_snapshot_id = create_snapshot(old_volume_id)
puts "Snapshotを作成 : " + new_snapshot_id
new_volume_id = create_volume(new_snapshot_id, input_size, instance_data["availability_zone"])
puts "新しいVolumeを作成 : " + new_volume_id

# Instanceスタート
start_instance(input_id)

# ファイル存在チェック
response = `#{ssh_str + "cat ssh_chk.txt"}`
if response != "cat: ssh_chk.txt: No such file or directory" then
    `#{ssh_str + "rm -f ssh_chk.txt"}`
    puts "Finish!!"
else
    puts "Error!!"
end

