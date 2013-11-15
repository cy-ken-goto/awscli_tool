require 'rubygems'
require 'json'
require 'pp'
require "open3"

# コマンド実行
def exec_command(cmd, put_flg=true)
    cmd = cmd.gsub(/[\r\n]/,"")
    if put_flg then
        puts cmd
    end

    ret = 1
    cnt = 0
    while  ret != 0 && cnt < 3
        if cnt > 0
            sleep(3)
            puts "[Retry " + cnt.to_s + "]"
        end
        stdout = `#{cmd}`
        ret = $?
        rtn = stdout.gsub(/[\r\n]/,"")
        cnt = cnt + 1
    end
    if ret != 0 then
        puts "[failed command] #{cmd}"
        exit(1)
    end
    return rtn
end

def get_instance_id(name)
    cmd = "aws ec2 describe-instances --filter Name=tag:Name,Values=" + name
    cmd += " | jq '.[\"Reservations\"][0][\"Instances\"][0][\"InstanceId\"]'"
    cmd += " | sed -e 's/\"//g'"
    return exec_command(cmd)
end

# クローン元のNameを渡しす。
# 同じ名付けをしているインスタンスリストを検索し、
# 数値がもっとも後ろのものに+1して返す
def get_instanse_tag_new_name(search_base)
    # 数字は外して検索
    search_base.gsub!(/\d*/, "")

    cmd = "aws ec2 describe-instances"
    cmd += " | jq '.[\"Reservations\"][][\"Instances\"][][\"Tags\"][]'"
    cmd += " | jq 'select(contains({Key:\"Name\"}))'"
    cmd += " | jq 'select(contains({Value:\"" + search_base + "\"}))'"
    cmd += " | jq '.[\"Value\"]'"
    cmd += " | sed -e 's/\"//g'"
    cmd += " | tr '\\n' ','"
    result = exec_command(cmd)
    result = result.chop
    instance_names = result.split(",")

    # 数字のIDを抽出
    instance_names_ids = Array.new
    i = 0
    while i < instance_names.length
        id = instance_names[i].gsub(/\D*/, "").to_i
        instance_names_ids << id
        i = i + 1
    end

    # ソートとして最後をカウントアップ
    instance_names_ids = instance_names_ids.sort
    new_id = instance_names_ids[-1] + 1

    return search_base + new_id.to_s
end

# Instance 各データを取得
def get_instance_data(instance_id)
    result = JSON.parse(exec_command("aws ec2 describe-instances --instance-ids " + instance_id))
    tags = result["Reservations"][0]["Instances"][0]["Tags"]
    name = ""
    i = 0
    while  i < tags.length
        if tags[i]["Key"] == "Name" then
            name = tags[i]["Value"]
        end
        i = i + 1
    end
    return {
                "private_ip"=>result["Reservations"][0]["Instances"][0]["PrivateIpAddress"], 
                "availability_zone"=>result["Reservations"][0]["Instances"][0]["Placement"]["AvailabilityZone"],
                "volume_id"=>result["Reservations"][0]["Instances"][0]["BlockDeviceMappings"][0]["Ebs"]["VolumeId"],
                "device_name"=>result["Reservations"][0]["Instances"][0]["BlockDeviceMappings"][0]["DeviceName"],
                "key_name"=>result["Reservations"][0]["Instances"][0]["KeyName"],
                "security_groups"=>result["Reservations"][0]["Instances"][0]["SecurityGroups"],
                "instance_type"=>result["Reservations"][0]["Instances"][0]["InstanceType"],
                "name"=>name
            }
end

def get_volume_id(volume_id)
    result = JSON.parse(exec_command("aws ec2 describe-volumes --volume-ids " + volume_id))
    return {
                "size"=>result["Volumes"][0]["Size"] 
            }
end

def create_instance(ami_id, instance_data, name="")
    i = 0
    security_group_ids = ""
    while i < instance_data["security_groups"].length
        security_group_ids += instance_data["security_groups"][i]["GroupId"] + " "
        i = i + 1
    end
    cmd ="aws ec2 run-instances --image-id " + ami_id
    cmd += " --key-name " + instance_data["key_name"]
    cmd += " --security-group-ids " + security_group_ids
    cmd += " --instance-type " + instance_data["instance_type"]
    cmd += " --placement AvailabilityZone=" + instance_data["availability_zone"]
    cmd += " | jq '.[\"Instances\"][0][\"InstanceId\"]'"
    cmd += " | sed -e 's/\"//g'"
    create_instance_id = exec_command(cmd)
    check_pend(create_instance_id, "running")
    if name != ""
        if ! create_name_tag(create_instance_id, name) then
            return false
        end
    end
    return create_instance_id
end

def create_name_tag(id, name)
    cmd = "aws ec2 create-tags"
    cmd += " --resources " + id
    cmd += " --tags Key=Name,Value=" + name
    cmd += " | jq .'[\"return\"]'"
    cmd += " | sed -e 's/\"//g'"
    if exec_command(cmd) == "true"
        return true
    end
    return false
end

def check_load_balancer(instance_id)
    cmd = "aws elb describe-load-balancers"
    cmd += " | jq '.[\"LoadBalancerDescriptions\"]'"
    load_balancers = JSON.parse(exec_command(cmd, put_flg=true))
    i = 0
    while i < load_balancers.length
        instances = load_balancers[i]["Instances"]
        j = 0
        while j < instances.length
            if instance_id == instances[j]["InstanceId"] then
                return load_balancers[i]["LoadBalancerName"]
            end
            j = j + 1
        end
        i = i + 1
    end
    return false
end

def register_instance_from_load_balancer(load_balancer_name, instance_id)
    cmd = "aws elb register-instances-with-load-balancer"
    cmd += " --load-balancer-name " + load_balancer_name
    cmd += " --instances " + instance_id
    cmd += " | jq '.[\"Instances\"][]'"
    cmd += " | jq 'select(contains({InstanceId:\"" + instance_id + "\"}))'"
    cmd += " | jq '.[\"InstanceId\"]'"
    cmd += " sed -e 's/\"//g'"
    if exec_command(cmd) != instance_id then
        return false
    end
    return check_pend_load_balancer(load_balancer_name, instance_id)
end

def deregister_instance_from_load_balancer(load_balancer_name, instance_id)
    cmd = "aws elb deregister-instances-from-load-balancer"
    cmd += " --load-balancer-name " + load_balancer_name
    cmd += " --instances " + instance_id
    result = JSON.parse(exec_command(cmd));
    while check_load_balancer(instance_id)
        print "."
        STDOUT.flush
        sleep 1
    end
    puts("deregist")
    return true
end

def check_pend_load_balancer(load_balancer_name, instance_id)
    cmd = "aws elb describe-instance-health"
    cmd += " --load-balancer-name " + load_balancer_name
    cmd += " --instances " + instance_id
    cmd += " | jq '.[\"InstanceStates\"][0][\"State\"]'"
    cmd += " sed -e 's/\"//g'"
    current_state = ""
    sleep_time = 3
    now_time = 0
    limit_time = 300
    while exec_command(cmd) != "In Service"
        print "."
        STDOUT.flush
        sleep sleep_time
        now_time = now_time + sleep_time
        if now_time >= limit_time
            puts current_state
            return false
        end
    end
    puts current_state
    return true
end

def create_image(instance_id, reboot=true)
    name = " \"" + Time.now.strftime("%Y%m%d%H%M%S_")
    name += "Created by " + instance_id + "\""
    cmd = "aws ec2 create-image --instance-id " + instance_id
    cmd += " --name " + name
    if reboot then
        cmd += " --reboot"
    else
        cmd += " --no-reboot"
    end
    result = JSON.parse(exec_command(cmd))
    check_pend(result["ImageId"], "available", 3)
    return result["ImageId"]
end

def create_snapshot(volume_id, instance_id=nil, description="")
    if !instance_id.nil? then
        description += " Created by " + instance_id
    else
        description += " Created by " + volume_id
    end
    description = " \""+ Time.now.strftime("%Y%m%d%H%M%S_") + description + "\""
    result = JSON.parse(exec_command("aws ec2 create-snapshot --volume-id " + volume_id + " --description" + description))
    check_pend(result["SnapshotId"], "completed", 3)
    return result["SnapshotId"]
end

def create_volume(snapshot_id, size, availability_zone)
    result = JSON.parse(exec_command("aws ec2 create-volume --snapshot-id " + snapshot_id + " --size " + size + " --availability-zone " + availability_zone))
    check_pend(result["VolumeId"], "available", 3)
    return result["VolumeId"]
end

def delete_snapshot(snapshot_id)
    result = JSON.parse(exec_command("aws ec2 delete-snapshot --snapshot-id " + snapshot_id))
    result["return"].class
    return result["return"]
end

def delete_volume(volume_id)
    result = JSON.parse(exec_command("aws ec2 delete-volume --volume-id " + volume_id))
    result["return"].class
    return result["return"]
end

# ec2インスタンスをstart
def start_instance(instance_id)
    if get_instance_state(instance_id) != "running" then
        puts "instance starting\n"
        result = JSON.parse(exec_command("aws ec2 start-instances --instance-ids " + instance_id))
        check_pend(instance_id, "running")
    end
end

# ec2インスタンスをstop
def stop_instance(instance_id)
    if get_instance_state(instance_id) != "stopped" then
        puts "instance stopping\n"
        result = JSON.parse(exec_command("aws ec2 stop-instances --instance-ids " + instance_id))
        check_pend(instance_id, "stopped")
    end
end

# ec2インスタンスをreboot
def reboot_instance(instance_id)
    if get_instance_state(instance_id) == "running" then
        puts "instance rebooting\n"
        result = JSON.parse(exec_command("aws ec2 reboot-instances --instance-ids " + instance_id))
        check_pend(instance_id, "running")
    end
end

# detach
def detach_volume(volume_id)
    puts "device detaching\n"
    result = JSON.parse(exec_command("aws ec2 detach-volume --volume-id " + volume_id))
    check_pend(volume_id, "available")
end

# attach
def attach_volume(volume_id, instance_id, device_name)
    puts "device attaching\n"
    result = JSON.parse(exec_command("aws ec2 attach-volume --volume-id " + volume_id + " --instance-id " + instance_id + " --device " + device_name))
    check_pend(volume_id, "in-use")
end

# penddingチェックメソッド
def check_pend(id, check_state, time=2)
    current_state = ""
    id_type = id.split("-")
    while current_state != check_state
        if current_state == "failed"
            return false
        end
        print "."
        STDOUT.flush
        if id_type[0] == "i" then
            current_state = get_instance_state(id)
        elsif id_type[0] == "snap" then
            current_state = get_snapshot_state(id)
        elsif id_type[0] == "vol" then
            current_state = get_volume_state(id)
        elsif id_type[0] == "ami" then
            current_state = get_ami_state(id)
        end
        sleep time
    end
    puts(current_state)
    return true
end

# Instance Stateを取得
def get_instance_state(instance_id)
    result = JSON.parse(exec_command("aws ec2 describe-instances --instance-ids " + instance_id, false))
    return result["Reservations"][0]["Instances"][0]["State"]["Name"]
end

# Snapshot Stateを取得
def get_snapshot_state(snapshot_id)
    result = JSON.parse(exec_command("aws ec2 describe-snapshots --snapshot-ids " + snapshot_id, false))
    return result["Snapshots"][0]["State"]
end

# Volume Stateを取得
def get_volume_state(volume_id)
    result = JSON.parse(exec_command("aws ec2 describe-volumes --volume-ids " + volume_id, false))
    return result["Volumes"][0]["State"]
end

# AMI Stateを取得
def get_ami_state(ami_id)
    result = JSON.parse(exec_command("aws ec2 describe-images --image-ids  " + ami_id, false))
    return result["Images"][0]["State"]
end

def input(print_str)
    input = ""
    while input == ""
        print(print_str)
        input = STDIN.gets
        input.chomp!
    end
    return input
end