target "binary" {
  dockerfile = "Dockerfile"
  target     = "binary-file"
  platforms  = ["linux/amd64", "linux/arm64"]
  output     = ["packages"]
}
