#!/bin/bash

# openGauss数据库自动安装脚本
# 适用于openEuler 22.03 ARM64系统
# 版本: openGauss 6.0.0

# 设置默认密码（可根据需要修改）
DEFAULT_PASSWORD="Admin@2025"
HOSTNAME=host01

# 主机名验证函数
validate_hostname() {
    local hostname=$1
    if [[ $hostname =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        return 0
    else
        return 1
    fi
}

# 获取本机IP地址
get_local_ip() {
    local ip=$(ip route get 1 2>/dev/null | awk '{print $7}' | head -1)
    if [[ -z "$ip" || "$ip" == "1" ]]; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    if [[ -z "$ip" ]]; then
        ip="127.0.0.1"
    fi
    echo $ip
}



set -e  # 遇到错误立即退出

echo "========================================="
echo "openGauss 6.0.0 自动安装脚本"
echo "适用系统: openEuler 22.03 ARM64"
echo "========================================="

# 检查系统版本
echo "检查系统版本..."
cat /etc/hostname
cat /etc/os-release | grep -E "NAME|VERSION"

# 智能主机名配置
echo "========================================="
echo "配置主机名..."
CURRENT_HOSTNAME=$(hostname)
echo "当前主机名: $CURRENT_HOSTNAME"

# 验证目标主机名格式
if ! validate_hostname "$HOSTNAME"; then
    echo "错误: 主机名格式不正确: $HOSTNAME"
    exit 1
fi

# 检查是否需要更改主机名
if [[ "$CURRENT_HOSTNAME" != "$HOSTNAME" ]]; then
    echo "需要将主机名从 '$CURRENT_HOSTNAME' 更改为 '$HOSTNAME'"
    
    # 更改主机名
    echo "正在更改主机名..."
    hostnamectl set-hostname ${HOSTNAME}
    echo ${HOSTNAME} > /etc/hostname
    
    # 验证更改结果
    NEW_HOSTNAME=$(hostname)
    if [[ "$NEW_HOSTNAME" == "$HOSTNAME" ]]; then
        echo "✅ 主机名更改成功: $NEW_HOSTNAME"
    else
        echo "❌ 主机名更改失败"
        exit 1
    fi
else
    echo "✅ 主机名已经是 '$HOSTNAME'，无需更改"
fi

# 显示主机名状态
echo "主机名配置状态:"
hostnamectl status | grep -E "Static hostname|Icon name|Machine ID"

# 获取网络配置
LOCAL_IP=$(get_local_ip)
echo "检测到本机IP地址: $LOCAL_IP"
echo "========================================="

# 步骤1: 下载openGauss安装包
echo "步骤1: 下载openGauss 6.0.0安装包..."
cd ~
if [ ! -f "openGauss-All-6.0.0-openEuler22.03-aarch64.tar.gz" ]; then
    echo "正在下载openGauss安装包..."
    wget https://opengauss.obs.cn-south-1.myhuaweicloud.com/6.0.0/openEuler22.03/arm/openGauss-All-6.0.0-openEuler22.03-aarch64.tar.gz
    echo "下载完成"
else
    echo "安装包已存在，跳过下载"
fi

# 步骤2: 安装必要工具
echo "步骤2: 安装必要工具..."
yum install tar expect -y


# 步骤3: 创建cluster_config.xml配置文件
echo "步骤4: 创建集群配置文件..."

cat > cluster_config.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<ROOT>
    <!-- openGauss整体信息 -->
    <CLUSTER>
        <PARAM name="clusterName" value="dbCluster" />
        <PARAM name="nodeNames" value="${HOSTNAME}" />
        <PARAM name="gaussdbAppPath" value="/opt/huawei/install/app" />
        <PARAM name="gaussdbLogPath" value="/var/log/omm" />
        <PARAM name="tmpMppdbPath" value="/opt/huawei/tmp" />
        <PARAM name="gaussdbToolPath" value="/opt/huawei/install/om" />
        <PARAM name="corePath" value="/opt/huawei/corefile" />
        <PARAM name="backIp1s" value="${LOCAL_IP}"/>
    </CLUSTER>
    <!-- 每台服务器上的节点部署信息 -->
    <DEVICELIST>
        <!-- 节点1上的部署信息 -->
        <DEVICE sn="${HOSTNAME}">
            <PARAM name="name" value="${HOSTNAME}"/>
            <PARAM name="azName" value="AZ1"/>
            <PARAM name="azPriority" value="1"/>
            <!-- 使用检测到的本机IP地址 -->
            <PARAM name="backIp1" value="${LOCAL_IP}"/>
            <PARAM name="sshIp1" value="${LOCAL_IP}"/>
            
            <!--dbnode-->
            <PARAM name="dataNum" value="1"/>
            <PARAM name="dataPortBase" value="15400"/>
            <PARAM name="dataNode1" value="/opt/huawei/install/data/dn"/>
            <PARAM name="dataNode1_syncNum" value="0"/>
        </DEVICE>
    </DEVICELIST>
</ROOT>
EOF

echo "✅ 集群配置文件创建完成"
echo "配置信息:"
echo "- 主机名: ${HOSTNAME}"
echo "- IP地址: ${LOCAL_IP}"
echo "- 数据库端口: 15400"

echo "集群配置文件已创建: cluster_config.xml"

# 步骤4: 创建安装目录
echo "步骤5: 创建安装目录..."
mkdir -p /opt/software/openGauss/script/

# 步骤5: 切换到安装目录
echo "步骤6: 切换到安装目录..."
cd /opt/software/openGauss

# 步骤6: 解压安装包
echo "步骤3: 解压openGauss安装包..."
tar -zxf ~/openGauss-All-6.0.0-openEuler22.03-aarch64.tar.gz

tar -zxf openGauss-OM-6.0.0-openEuler22.03-aarch64.tar.gz

# 步骤7: 复制配置文件
echo "步骤8: 复制配置文件..."
cp ~/cluster_config.xml .

# 步骤8: 设置目录权限
echo "步骤9: 设置目录权限..."
chmod 755 -R /opt/software

# 步骤10: 执行预安装
echo "步骤10: 执行预安装..."
cd /opt/software/openGauss/script/



echo "正在执行预安装，这可能需要几分钟时间..."
echo "将自动创建omm用户并设置密码为: ${DEFAULT_PASSWORD}"
echo ""

# 使用expect自动化输入
expect << EOF
set timeout 300
log_user 1
spawn ./gs_preinstall -U omm -G dbgrp -X /opt/software/openGauss/cluster_config.xml

expect {
    -re "Are you sure you want to create the user.*\\(yes/no\\)\\?" {
        send "yes\r"
        exp_continue
    }
    -re "Please enter password for cluster user\\..*Password:" {
        send "${DEFAULT_PASSWORD}\r"
        exp_continue
    }
    -re "Please enter password for cluster user again\\..*Password:" {
        send "${DEFAULT_PASSWORD}\r"
        exp_continue
    }
    -re "Password:" {
        send "${DEFAULT_PASSWORD}\r"
        exp_continue
    }
    "Preinstallation succeeded" {
        puts "预安装成功完成"
    }
    timeout {
        puts "操作超时"
        exit 1
    }
    eof {
        puts "预安装进程结束"
    }
}
EOF

echo "预安装完成！"
echo ""
echo "========================================="
echo "预安装已完成，omm用户已创建"
echo "用户名: omm"
echo "密码: ${DEFAULT_PASSWORD}"
echo ""
echo "开始执行数据库安装..."
echo "========================================="

# 切换到omm用户并执行安装
echo "正在切换到omm用户并执行数据库安装..."
su - omm << 'OMMSUDO'
cd /opt/software/openGauss

# 使用expect自动化数据库安装过程
expect << EOF
set timeout 600
log_user 1
spawn gs_install -X /opt/software/openGauss/cluster_config.xml

expect {
    -re "Please enter password for database:.*" {
        send "Admin@2025\r"
        exp_continue
    }
    -re "Please repeat for database:.*" {
        send "Admin@2025\r"
        exp_continue
    }
    -re "Password:.*" {
        send "Admin@2025\r"
        exp_continue
    }
    "Installation succeeded" {
        puts "数据库安装成功完成"
    }
    "completed successfully" {
        puts "安装成功完成"
    }
    timeout {
        puts "安装超时"
        exit 1
    }
    eof {
        puts "安装进程结束"
    }
}

# 检查数据库状态
puts "正在检查数据库状态..."
spawn gs_om -t status

expect {
    "cluster_state" {
        puts "数据库状态检查完成"
    }
    timeout {
        puts "状态检查超时"
    }
    eof
}
EOF

OMMSUDO

echo ""
echo "========================================="
echo "openGauss数据库安装完成！"
echo ""
echo "数据库信息："
echo "- 用户名: omm"
echo "- 用户密码: ${DEFAULT_PASSWORD}"
echo "- 数据库密码: ${DEFAULT_PASSWORD}"
echo "- 数据库端口: 15400"
echo ""
echo "常用命令："
echo "1. 查看数据库状态: gs_om -t status"
echo "2. 连接数据库: gsql -d postgres -p 15400"
echo "3. 启动数据库: gs_om -t start"
echo "4. 停止数据库: gs_om -t stop"
echo "========================================="
echo ""
echo "注意事项："
echo "- 请确保系统已关闭防火墙和SELinux"
echo "- 请确保系统时间同步"
echo "- 如果遇到权限问题，请检查用户和组是否正确创建"
echo "- 默认数据库端口为15400"
echo "- omm用户密码为: ${DEFAULT_PASSWORD}"
echo ""
echo "安装脚本执行完成！"