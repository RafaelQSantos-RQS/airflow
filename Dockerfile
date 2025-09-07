ARG AIRFLOW_BUILD_VERSION="3.0.6"
ARG PYTHON_BUILD_VERSION="3.12"

FROM apache/airflow:slim-${AIRFLOW_BUILD_VERSION}-python${PYTHON_BUILD_VERSION}

ARG AIRFLOW_BUILD_VERSION \
    PYTHON_BUILD_VERSION

COPY requirements.txt /

RUN pip install --no-cache-dir -r /requirements.txt \
    --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_BUILD_VERSION}/constraints-${PYTHON_BUILD_VERSION}.txt"
