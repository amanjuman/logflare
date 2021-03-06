defmodule Logflare.Logs.IngestTransformerTest do
  @moduledoc false
  use ExUnit.Case
  import Logflare.Logs.IngestTransformers

  describe "BQ spec transformations" do
    @batch [
      %{
        "metadata" => %{
          "level-1-dashed-key" => "value",
          "level1" => %{
            "level2" => %{
              "dashed-key" => "value"
            }
          }
        }
      },
      %{
        "metadata" => %{
          "level1" => [
            %{
              "level2" => %{
                "dashed-key-more-dashes" => "value"
              }
            }
          ]
        }
      },
      %{
        "metadata" => %{
          "level1" => [
            %{
              "level2" => %{
                "dashed-key-more-dashes" => "value"
              }
            }
          ]
        }
      }
    ]
    test "dashes to underscores" do
      assert transform(@batch, [:dashes_to_underscores]) == [
               %{
                 "metadata" => %{
                   "level_1_dashed_key" => "value",
                   "level1" => %{"level2" => %{"dashed_key" => "value"}}
                 }
               },
               %{
                 "metadata" => %{
                   "level1" => [%{"level2" => %{"dashed_key_more_dashes" => "value"}}]
                 }
               },
               %{
                 "metadata" => %{
                   "level1" => [%{"level2" => %{"dashed_key_more_dashes" => "value"}}]
                 }
               }
             ]
    end

    @batch [
      %{
        "metadata" => %{
          "1level_key" => "value",
          "1level_key" => %{
            "2level_key" => %{
              "3level_key" => "value"
            }
          }
        }
      },
      %{
        "metadata" => %{
          "1level_key" => [
            %{
              "2level_key" => %{
                "3level_key" => "value"
              }
            }
          ]
        }
      },
      %{
        "metadata" => %{
          "1level" => [
            %{
              "2level" => %{
                "311level_key" => "value",
                3 => "value"
              }
            }
          ]
        }
      }
    ]
    test "alter leading numbers" do
      assert transform(@batch, [:alter_leading_numbers]) == [
               %{
                 "metadata" => %{
                   "onelevel_key" => %{
                     "twolevel_key" => %{"threelevel_key" => "value"}
                   }
                 }
               },
               %{
                 "metadata" => %{
                   "onelevel_key" => [
                     %{
                       "twolevel_key" => %{
                         "threelevel_key" => "value"
                       }
                     }
                   ]
                 }
               },
               %{
                 "metadata" => %{
                   "onelevel" => [
                     %{
                       "twolevel" => %{
                         3 => "value",
                         "three11level_key" => "value"
                       }
                     }
                   ]
                 }
               }
             ]
    end

    @batch [
      %{
        "metadata" => %{
          "level_1_key_!@#$%%^&*(" => %{
            "level_2_key+{}:\"<>?\"" => %{"threelevel_key" => "value"}
          }
        }
      },
      %{
        "metadata" => %{
          "1level_key" => [
            %{
              "2level_key" => %{
                "3level_key ,.~" => "value"
              }
            }
          ]
        }
      },
      %{
        "metadata" => %{
          "1level" => [
            %{
              "2level" => %{
                "3!!level_key" => "value"
              }
            }
          ]
        }
      }
    ]
    test "alphanumeric only" do
      assert transform(@batch, [:alphanumeric_only]) == [
               %{
                 "metadata" => %{
                   "level_1_key_" => %{
                     "level_2_key" => %{"threelevel_key" => "value"}
                   }
                 }
               },
               %{
                 "metadata" => %{
                   "1level_key" => [
                     %{"2level_key" => %{"3level_key" => "value"}}
                   ]
                 }
               },
               %{
                 "metadata" => %{
                   "1level" => [
                     %{"2level" => %{"3level_key" => "value"}}
                   ]
                 }
               }
             ]
    end

    @batch [
      %{
        "metadata" => %{
          "level_1_key_" => %{
            "_FILE_level_2_key_FILE_" => %{"threelevel_key" => "value"}
          }
        }
      },
      %{
        "metadata" => %{
          "_PARTITION_1level_key" => [
            %{"_FILE_2level_key_PARTITION_" => %{"3level_key" => "value"}}
          ]
        }
      },
      %{
        "metadata" => %{
          "_TABLE_1level" => [
            %{"2level" => %{"3level_key" => "value"}}
          ]
        }
      }
    ]
    test "strip bq prefixes" do
      assert transform(@batch, [:strip_bq_prefixes]) == [
               %{
                 "metadata" => %{
                   "level_1_key_" => %{
                     "level_2_key_FILE_" => %{"threelevel_key" => "value"}
                   }
                 }
               },
               %{
                 "metadata" => %{
                   "1level_key" => [%{"2level_key_PARTITION_" => %{"3level_key" => "value"}}]
                 }
               },
               %{
                 "metadata" => %{
                   "1level" => [%{"2level" => %{"3level_key" => "value"}}]
                 }
               }
             ]
    end
  end
end
