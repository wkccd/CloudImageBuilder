# 将Imagebuilder默认repositories 切换到镜像源 避免下载失败
OFFICIAL="https://downloads.immortalwrt.org"
MIRROR="https://mirrors.cernet.edu.cn/immortalwrt"
echo ">>> official failed, switching to mirror"
BASE_URL="$MIRROR"
echo "Using BASE_URL = $BASE_URL"
echo "========================================"
echo "Updating repositories.conf"
echo "========================================"
sed -i "s#${OFFICIAL}#${BASE_URL}#g" repositories.conf
cat repositories.conf