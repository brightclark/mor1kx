pipeline {
    agent any

    stages {
        stage("Docker pull") {
            steps {
                sh 'docker pull librecores/librecores-ci-openrisc'
                sh 'docker images'
            }
        }

       stage("Yosys synthesis"){
            environment {
                TOPLEVEL = "mor1kx"
  		        VERSION = "5.0-r3"
             }
            steps{
               sh 'docker run --rm -v $(pwd):/src -e "TOPLEVEL=$TOPLEVEL" -e "VERSION=$VERSION" librecores/librecores-ci-openrisc  /yosys-scripts/yosys.sh'
            }
        }

        stage('Performance tests') {
            steps {
                echo "-=- execute performance tests -=-"
                perfReport 'output.csv'
            }
        }

        stage("Docker run") {
            parallel {
                stage("verilator") {
                    environment{
                        JOB = 'verilator'
                    }
                    steps {
                        dockerrun()
                    }
                }
                stage("testing 1") {
                    environment {
                        JOB = 'or1k-tests'
                        SIM = 'icarus'
                        PIPELINE = 'CAPPUCCINO'
                        EXPECTED_FAILURES="or1k-cy"
                    }
                    steps {
                        dockerrun()
                    }
                }
                stage("testing 2") {
                    environment {
                        JOB = 'or1k-tests'
                        SIM = 'icarus'
                        PIPELINE = 'CAPPUCCINO'
                        EXPECTED_FAILURES="or1k-cy"
                        EXTRA_CORE_ARGS="--feature_dmmu NONE"
                    }
                    steps {
                        dockerrun()
                    }
                }
                stage("testing 3") {
                    environment {
                        JOB = 'or1k-tests'
                        SIM = 'icarus'
                        PIPELINE = 'CAPPUCCINO'
                        EXPECTED_FAILURES = "or1k-cy or1k-dsxinsn"
                        EXTRA_CORE_ARGS = "--feature_immu NONE"
                    }
                    steps {
                        dockerrun()
                    }
                }
                stage("testing 4") {
                    environment {
                        JOB = 'or1k-tests'
                        SIM = 'icarus'
                        PIPELINE = 'CAPPUCCINO'
                        EXPECTED_FAILURES = "or1k-cy"
                        EXTRA_CORE_ARGS = "--feature_datacache NONE"
                    }
                    steps {
                        dockerrun()
                    }
                }
                stage("testing 5") {
                    environment {
                        JOB = 'or1k-tests'
                        SIM = 'icarus'
                        PIPELINE = 'CAPPUCCINO'
                        EXPECTED_FAILURES = "or1k-cy"
                        EXTRA_CORE_ARGS = "--feature_instructioncache NONE"
                    }
                    steps {
                        dockerrun()
                    }
                }
                stage("testing 6") {
                    environment {
                        JOB = 'or1k-tests'
                        SIM = 'icarus'
                        PIPELINE = 'CAPPUCCINO'
                        EXPECTED_FAILURES = "or1k-cy"
                        EXTRA_CORE_ARGS = "--feature_debugunit NONE"
                    }
                    steps {
                        dockerrun()
                    }
                }
                stage("testing 7") {
                    environment {
                        JOB = 'or1k-tests'
                        SIM = 'icarus'
                        PIPELINE = 'CAPPUCCINO'
                        EXPECTED_FAILURES = "or1k-cy or1k-cmov"
                        EXTRA_CORE_ARGS = "--feature_cmov NONE"
                    }
                    steps {
                        dockerrun()
                    }
                }
                stage("testing 8") {
                    environment {
                        JOB = 'or1k-tests'
                        SIM = 'icarus'
                        PIPELINE = 'CAPPUCCINO'
                        EXPECTED_FAILURES = "or1k-cy or1k-ext"
                        EXTRA_CORE_ARGS = "--feature_ext NONE"
                    }
                    steps {
                        dockerrun()
                    }
                }
                stage("testing 9") {
                    environment {
                        JOB = 'or1k-tests'
                        SIM = 'icarus'
                        PIPELINE = 'ESPRESSO'
                    }
                    steps {
                        script {
                            //TODO: remove try/catch once the failing test is fixed (https://github.com/openrisc/mor1kx/issues/71)
                            try {
                                dockerrun()
                            } catch (Exception e) {
                                echo "Allowed failure"
                            }
                        }
                    }
                }
            }
        }
    }
}

void dockerrun() {
    sh 'docker run --rm -v $(pwd):/src -e "JOB=$JOB" -e "SIM=$SIM" -e "PIPELINE=$PIPELINE" -e "EXPECTED_FAILURES=$EXPECTED_FAILURES" -e "EXTRA_CORE_ARGS=$EXTRA_CORE_ARGS" librecores/librecores-ci-openrisc /src/.travis/test.sh'
}
