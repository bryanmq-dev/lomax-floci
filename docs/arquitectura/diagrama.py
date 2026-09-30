"""Etapa 1 - Diagrama de arquitectura de Lomax SA sobre FLOCI.
Genera docs/arquitectura/diagrama-arquitectura.png con iconos oficiales AWS/K8s.
Requiere: pip install diagrams  +  graphviz instalado en el sistema (binario `dot`).
"""
from diagrams import Diagram, Cluster, Edge
from diagrams.aws.database import RDS, Dynamodb
from diagrams.aws.storage import SimpleStorageServiceS3
from diagrams.aws.compute import Lambda, EC2ContainerRegistry as ECRIcon
from diagrams.onprem.network import Nginx
from diagrams.onprem.client import User
from diagrams.k8s.compute import Pod, Deploy
from diagrams.k8s.network import SVC

graph_attr = {"fontsize": "22", "bgcolor": "white"}

with Diagram(
    "Lomax SA - Catalogo de productos (entorno local FLOCI, puerto 4566)",
    filename="docs/arquitectura/diagrama-arquitectura",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
):
    usuario = User("Vendedor / Cliente\n(navegador)")

    with Cluster("Docker Compose / kind (namespace lomax)\nred bridge local"):
        proxy = Nginx("proxy\n:8090 -> 80\nHTTP")
        frontend = Nginx("frontend (estatico)\nregistrar/catalogo/detalle\n:80")

        with Cluster("Kubernetes - clúster kind 'lomax-eks'\n(EKS local, FLOCI solo simula la API de control)"):
            svc = SVC("Service backend\nClusterIP")
            with Cluster("Deployment backend (1 a 3 replicas)"):
                pods = [Pod("Pod backend #1"), Pod("Pod backend #2"), Pod("Pod backend #3")]
            deploy = Deploy("Deployment backend\nimagen: ECR lomax/backend:<sha>")

    with Cluster("FLOCI - emulador local AWS (http://localhost:4566)"):
        rds = RDS("RDS Postgres\nlomax-db\n:5432\ncategorias, productos")
        dynamo = Dynamodb("DynamoDB\nLomaxAtributos\nPK producto_id")
        s3_orig = SimpleStorageServiceS3("S3\nlomax-originales")
        s3_mini = SimpleStorageServiceS3("S3\nlomax-miniaturas")
        lam = Lambda("Lambda\nlomax-generar-miniatura\n(resize <=300x300)")
        ecr = ECRIcon("ECR\nlomax/backend\nlomax/frontend")

    usuario >> Edge(label="HTTP :8090") >> proxy
    proxy >> Edge(label="/") >> frontend
    proxy >> Edge(label="/api") >> svc
    svc >> pods
    deploy >> pods

    pods >> Edge(label="SQL :5432 (host-gateway 10.0.0.1)") >> rds
    pods >> Edge(label="AWS SDK :4566") >> dynamo
    pods >> Edge(label="AWS SDK :4566") >> s3_orig
    pods >> Edge(label="invoke sincrono") >> lam
    lam >> Edge(label="lee") >> s3_orig
    lam >> Edge(label="escribe miniatura") >> s3_mini
    lam >> Edge(label="actualiza estado") >> dynamo
    ecr >> Edge(label="docker pull / kind load", style="dashed") >> deploy

print("Diagrama generado en docs/arquitectura/diagrama-arquitectura.png")
