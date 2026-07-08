# docker buildx bake 多架构构建编排
# 用法:
#   docker buildx bake --load      # 本地加载（单架构时）
#   docker buildx bake --push      # 推送到 registry（需先 docker login）
#   docker buildx bake openvohive  # 只构建单个 target

group "default" {
  targets = ["openvohive", "vohive-legacy", "dji2quectel"]
}

variable "REGISTRY" {
  default = ""
}

target "openvohive" {
  context    = "."
  dockerfile = "openvohive/Dockerfile"
  platforms  = ["linux/amd64", "linux/arm64"]
  tags = compact([
    "openvohive:latest",
    REGISTRY != "" ? "${REGISTRY}/openvohive:latest" : "",
  ])
}

target "vohive-legacy" {
  context    = "."
  dockerfile = "vohive-legacy/Dockerfile"
  platforms  = ["linux/amd64", "linux/arm64"]
  tags = compact([
    "vohive-legacy:latest",
    REGISTRY != "" ? "${REGISTRY}/vohive-legacy:latest" : "",
  ])
}

target "dji2quectel" {
  context    = "./dji2quectel"
  platforms  = ["linux/amd64", "linux/arm64"]
  tags = compact([
    "dji2quectel:latest",
    REGISTRY != "" ? "${REGISTRY}/dji2quectel:latest" : "",
  ])
}
