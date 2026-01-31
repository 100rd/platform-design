output "hpa_names" {
  description = "Names of created HPAs"
  value = compact([
    var.enabled ? "coredns" : "",
  ])
}
