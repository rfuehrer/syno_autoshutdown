#!/usr/bin/env python2.7

import os
import SocketServer
import argparse
from BaseHTTPServer import BaseHTTPRequestHandler

class MyHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type','text/html')
        self.end_headers()

        if self.path == my_apath:
            print "shutdown_function got called"
            self.wfile.write("System will be shut down now...")

            import subprocess
            import shlex
            cmd = shlex.split("sudo shutdown -h now")
            subprocess.call(cmd)

            #os.system("shutdown /s /t 1")

        if self.path == my_spath:
            # self.wfile.write("<p align='center'><font size='32'><a href='"+my_apath+"'>execute shutdown now</a></font><p>")
            self.wfile.write("<!DOCTYPE html><html><link rel='stylesheet' href='https://www.w3schools.com/w3css/4/w3.css'><style>.w3-button {width:250px;} a{text-decoration: none;}</style><body><div class='w3-container'><p align='center'><button class='w3-button w3-red'><a href='"+my_apath+"'>Execute Shutdown NOW</a></button></p></div></body></html>")

        if self.path == my_tpath:
            print "test_function got called"
            self.wfile.write("Webserver test mode is working...")

parser = argparse.ArgumentParser(description='Synology Autoshutdown Webserver!')
parser.add_argument("--port", default=8080, type=int, help="Port of webserver")
parser.add_argument("--spath", default="/shutdown", type=str, help="Shutdown path of shutdown listener")
parser.add_argument("--tpath", default="/test", type=str, help="Test path of shutdown listener")
parser.add_argument("--uuid", required=True, type=str, help="UUID of shutdown listener")

args = parser.parse_args()

my_apath = "/" + args.uuid + "/"+ args.spath +"-action"
my_spath = "/" + args.uuid + "/"+ args.spath
my_tpath = "/" + args.uuid + "/" +args.tpath
my_port = args.port

httpd = SocketServer.TCPServer(("", my_port), MyHandler)
httpd.serve_forever()