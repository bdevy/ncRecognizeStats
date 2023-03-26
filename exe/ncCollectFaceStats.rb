#!/usr/bin/env ruby


require 'pry-byebug'
require 'zabbix_sender_api'
require 'optimist'
require 'mysql'
require 'cgi'

opts = Optimist::options do
  opt :zabhost, "Zabbix host to attach data to", :type => :string, :required => true
  opt :zabproxy, "Zabbix proxy/server to send data to", :type => :string, :required => true
  opt :zabsender, "Path to Zabbix Sender", :type => :string, :default => "/usr/bin/zabbix_sender"
  opt :mysqlhost, "Hostname or IP of mysql DB host", :type => :string, :default => "127.0.0.1"
  opt :mysqluser, "Username of mysql DB", :type => :string, :required => true
  opt :mysqlpass, "Password of mysql DB", :type => :string, :required => true
  opt :mysqlport, "Port of mysql DB", :type => :string, :default => "3306"
end

batch = Zabbix::Sender::Batch.new(hostname: opts[:zabhost])
disco = Zabbix::Sender::Discovery.new(key: "facestats")

qryFacesDetected = "SELECT oc_recognize_face_detections.cluster_id AS cluster_id, oc_recognize_face_clusters.title AS cluster_title, COUNT(oc_recognize_face_detections.cluster_id) AS total_faces, oc_recognize_face_clusters.user_id AS user_id FROM oc_recognize_face_detections INNER JOIN oc_recognize_face_clusters ON oc_recognize_face_detections.cluster_id=oc_recognize_face_clusters.id GROUP BY oc_recognize_face_detections.cluster_id ORDER BY oc_recognize_face_clusters.user_id ASC,count(oc_recognize_face_detections.cluster_id) DESC"

qryNullClusters = "SELECT COUNT(*) FROM oc_recognize_face_detections WHERE cluster_id IS null"

qryTotalFaces = "SELECT COUNT(*) FROM oc_recognize_face_detections"

qryTotalClusters = "SELECT COUNT(*) FROM oc_recognize_face_clusters"

qryQueuedFaces = "SELECT COUNT(*) FROM oc_recognize_queue_faces"

ncdb = Mysql.connect("mysql://#{opts[:mysqluser]}:#{CGI.escape(opts[:mysqlpass])}@#{opts[:mysqlhost]}:3306/nextcloud?charset=utf8mb4")

ncdb.query(qryFacesDetected).each {|cluster_id,cluster_title,total_faces,user_id|
  disco.add_entity(:CLUSTER_ID => cluster_id, :CLUSTER_TITLE => cluster_title, :USER_ID => user_id)
  batch.addItemData(key: "totalFaces[#{cluster_id}]", value: total_faces)
}

nullFaceClusters = ncdb.query(qryNullClusters).entries.first.first
totalFaces = ncdb.query(qryTotalFaces).entries.first.first
totalFaceClusters = ncdb.query(qryTotalClusters).entries.first.first
totalQueuedFaces = ncdb.query(qryQueuedFaces).entries.first.first

batch.addItemData(key: "nullFaceClusters", value: nullFaceClusters)
batch.addItemData(key: "totalFaceDetections", value: totalFaces)
batch.addItemData(key: "totalFaceClusters", value: totalFaceClusters)
batch.addItemData(key: "totalFacesQueued", value: totalQueuedFaces)

batch.addDiscovery(disco)

sender = Zabbix::Sender::Pipe.new

puts sender.sendBatchAtomic(batch)
