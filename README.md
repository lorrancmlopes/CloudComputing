# CloudComputing


Projeto detalhado no site.
Caso queria apenas rodar sem seguir o roteiro, clone e rode os comandos abaixo:

```
export AWS_ACCESS_KEY_ID=<ID_CHAVE_DE_ACESSO>
export AWS_SECRET_ACCESS_KEY=<CHAVE_SECRETA_DE_ACESSO>
export AWS_DEFAULT_REGION="us-east-1"
cd terraform
terraform init
terraform plan
terraform apply -var="email=seu_email@gmail.com" -auto-approve
```
