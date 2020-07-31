apply_hcs:
	cd hcs && terraform init
	cd hcs && terraform apply --auto-approve

destroy_hcs:
	cd hcs && terraform destroy --auto-approve

output_hcs:
	cd hcs && terraform output

apply_payments:
	cd payments-vm && terraform init
	cd payments-vm && terraform apply --auto-approve

destroy_payments:
	cd payments-vm && terraform destroy --auto-approve

output_payments:
	cd payments-vm && terraform output

apply_aks:
	cd aks && terraform init
	cd aks && terraform apply --auto-approve

destroy_aks:
	cd aks && terraform destroy --auto-approve

output_aks:
	cd aks && terraform output

output_aks_kubeconfig:
	cd aks && terraform output frontend_kube_config > ../kubeconfig.yaml

apply: apply_hcs apply_payments apply_aks

destroy: destroy_aks destroy_payments destroy_hcs