require 'rubygems'
require 'json'
require 'pp'

# Instance 各データを取得
def get_instance_data(instance_id)
    cmd = "aws ec2 describe-instances --instance-ids " + instance_id
    puts cmd
    result = JSON.parse(`#{cmd}`)
    return {
                "private_ip"=>result["Reservations"][0]["Instances"][0]["PrivateIpAddress"], 
                "availability_zone"=>result["Reservations"][0]["Instances"][0]["Placement"]["AvailabilityZone"],
                "volume_id"=>result["Reservations"][0]["Instances"][0]["BlockDeviceMappings"][0]["Ebs"]["VolumeId"],
                "device_name"=>result["Reservations"][0]["Instances"][0]["BlockDeviceMappings"][0]["DeviceName"]
            }
end

def create_snapshot(volume_id)
    cmd = "aws ec2 create-snapshot --volume-id " + volume_id
    puts cmd
    result = JSON.parse(`#{cmd}`)
    check_pend(result["SnapshotId"], "completed")
    return result["SnapshotId"]
end

def create_volume(snapshot_id, size, availability_zone)
    cmd = "aws ec2 create-volume --snapshot-id " + snapshot_id + " --size " + size + " --availability-zone " + availability_zone
    puts cmd
    result = JSON.parse(`#{cmd}`)
    check_pend(result["VolumeId"], "available")
    return result["VolumeId"]
end

# ec2インスタンスをstart
def start_instance(instance_id)
    if get_instance_state(instance_id) != "running" then
        cmd = "aws ec2 start-instances --instance-ids " + instance_id
        puts cmd
        puts "instance starting\n"
        result = JSON.parse(`#{cmd}`)
        check_pend(instance_id, "running")
    end
end

# ec2インスタンスをstop
def stop_instance(instance_id)
    if get_instance_state(instance_id) != "stopped" then
        cmd = "aws ec2 stop-instances --instance-ids " + instance_id
        puts cmd
        puts "instance stopping\n"
        result = JSON.parse(`#{cmd}`)
        check_pend(instance_id, "stopped")
    end
end

# detach
def detach_volume(volume_id)
    cmd = "aws ec2 detach-volume --volume-id " + volume_id
    puts cmd
    puts "device detaching\n"
    result = JSON.parse(`#{cmd}`)
    check_pend(volume_id, "available")
end

# attach
def attach_volume(volume_id, instance_id, device_name)
    cmd = "aws ec2 attach-volume --volume-id " + volume_id + " --instance-id " + instance_id + " --device " + device_name
    puts cmd
    puts "device attaching\n"
    result = JSON.parse(`#{cmd}`)
    check_pend(volume_id, "in-use")
end

# penddingチェックメソッド
def check_pend(id, check_state)
    current_state = ""
    id_type = id.split("-")
    while current_state != check_state
        puts "."
        if id_type[0] == "i" then
            current_state = get_instance_state(id)
        elsif id_type[0] == "snap" then
            current_state = get_snapshot_state(id)
        elsif id_type[0] == "vol" then
            current_state = get_volume_state(id)
        end
        sleep 3
    end
    print(current_state + "\n")
end

# Instance Stateを取得
def get_instance_state(instance_id)
    cmd = "aws ec2 describe-instances --instance-ids " + instance_id
    #puts cmd
    result = JSON.parse(`#{cmd}`)
    return result["Reservations"][0]["Instances"][0]["State"]["Name"]
end

# Snapshot Stateを取得
def get_snapshot_state(snapshot_id)
    cmd = "aws ec2 describe-snapshots --snapshot-ids " + snapshot_id
    #puts cmd
    result = JSON.parse(`#{cmd}`)
    return result["Snapshots"][0]["State"]
end

# Volume Stateを取得
def get_volume_state(volume_id)
    cmd = "aws ec2 describe-volumes --volume-ids " + volume_id
    #puts cmd
    result = JSON.parse(`#{cmd}`)
    return result["Volumes"][0]["State"]
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

input_id.chomp!
key_file.chomp!
input_size.chomp!

instance_data = get_instance_data(input_id)
ssh_str = "ssh -i " + key_file + " root@" + instance_data["private_ip"] + " "
# チェック用ファイル作成
`#{ssh_str + "touch ssh_chk.txt"}`

# dfコマンドで対象サーバのルートデバイスを取得
device_pos = `#{ssh_str + "df -x tmpfs | grep / | cut -d' ' -f1"}`

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

# ファイル存在チェック
response = `#{ssh_str + "cat ssh_chk.txt"}`
if response != "cat: ssh_chk.txt: No such file or directory" then
    `#{ssh_str + "rm -f ssh_chk.txt"}`
    puts "Finish!!"
else
    puts "Error!!"
end

