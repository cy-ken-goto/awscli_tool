#!/bin/env ruby
require 'aws_include.rb'

# コマンドライン引数受取
require 'optparse'

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

        opts.parse!(ARGV)

    rescue => e
        puts opts.help
        puts
        puts e.message
        exit 1
    end
end

if !config[:instance_id].nil? then
    input_instance_id = config[:instance_id]
elsif !config[:name].nil? then
    input_instance_id = get_instance_id(config[:name])
else
    input_id = input("クローン元のEC2インスタンスのidを入力して下さい : ")
end


