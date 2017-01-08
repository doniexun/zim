// Copyright © 2017 Zhang Peihao <zhangpeihao@gmail.com>
//

package cmd

import (
	"fmt"
	"github.com/spf13/cobra"
	"github.com/zhangpeihao/zim/pkg/invoker/driver/httpapi"
	"github.com/zhangpeihao/zim/pkg/protocol"
	"github.com/zhangpeihao/zim/pkg/protocol/serialize"
	"github.com/zhangpeihao/zim/pkg/util"
	"log"
	"net"
	"net/http"
	"os"
	"time"
)

var (
	userIDQueue = make(chan string, 1000)
	p2uCommand  = `t1
test
p2u
{"useridlist":"%s"}
foo bar
`
)

var (
	loginResponse = &protocol.Command{
		Version: "t1",
		AppID:   cfgAppID,
		Name:    "login",
		Data:    nil,
		Payload: []byte("foo bar"),
	}
)

// stubCmd represents the stub command
var stubCmd = &cobra.Command{
	Use:   "stub",
	Short: "测试用桩服务",
	Long: `测试用桩服务

提供桩服务，接收Gateway消息，并回消息`,
	Run: func(cmd *cobra.Command, args []string) {
		http.HandleFunc("/login", HandleLogin)
		http.HandleFunc("/msg", HandleMsg)
		listener, err := net.Listen("tcp", cfgStubBindAddress)
		if err != nil {
			log.Fatal("listen error:", err)
			return
		}
		go func() {
			servererr := http.Serve(listener, nil)
			if servererr != nil {
				log.Fatal("Serve error:", err)
				if !IsExit() {
					os.Exit(1)
				}
			}
		}()
		terminationSignalsCh := make(chan os.Signal, 1)
		util.WaitAndClose(terminationSignalsCh, time.Second*time.Duration(3), func() {
			SetExitFlag()
		})
	},
}

func init() {
	RootCmd.AddCommand(stubCmd)

	stubCmd.PersistentFlags().StringVar(&cfgStubBindAddress, "stub-addr", ":8880", "service stub绑定地址")
	stubCmd.PersistentFlags().StringVar(&cfgAppID, "appid", "test", "App ID")

}

// HandleLogin 登入处理
func HandleLogin(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get(httpapi.HeaderUserID)
	appID := r.Header.Get(httpapi.HeaderAppID)
	log.Printf("HandleLogin(%s, %s)\n", userID, appID)
	w.WriteHeader(200)
	msg, err := serialize.Compose(loginResponse)
	if err != nil {
		w.WriteHeader(500)
	} else {
		w.Write(msg)
	}
}

// HandleMsg 消息处理
func HandleMsg(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get(httpapi.HeaderUserID)
	appID := r.Header.Get(httpapi.HeaderAppID)

	if len(userID) == 0 {
		w.WriteHeader(400)
		log.Printf("HandleMsg() plaintext.ParseReader no %s header\n", httpapi.HeaderUserID)
		return
	}
	if len(appID) == 0 {
		w.WriteHeader(400)
		log.Printf("HandleMsg() plaintext.ParseReader no %s header\n", httpapi.HeaderAppID)
		return
	}

	userIDQueue <- userID
	toUserID := <-userIDQueue
	w.Write([]byte(fmt.Sprintf(p2uCommand, toUserID)))
}