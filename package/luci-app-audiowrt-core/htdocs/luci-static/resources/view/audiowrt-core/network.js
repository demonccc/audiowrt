'use strict';
'require view';
'require uci';
'require fs';
'require ui';

return view.extend({
	load: function() { return uci.load('audiowrt'); },
	render: function() {
		var self=this, provisioning=uci.get('audiowrt','main','provisioning')==='1', ssid=uci.get('audiowrt','main','wifi_ssid')||'-', error=uci.get('audiowrt','main','last_error')||'';
		return E('div',{'class':'cbi-map'},[
			E('h2',{},_('AudioWRT Network')),
			E('div',{'class':'cbi-section'},[
				E('p',{},_('AudioWRT uses Ethernet and Wi-Fi as clients. It does not provide a normal router/NAT role.')),
				E('p',{},[E('strong',{},_('Wi-Fi: ')),provisioning?_('Provisioning mode'):ssid]),
				error?E('p',{'class':'alert-message warning'},error):'',
				E('button',{'class':'btn cbi-button-action','click':function(){self.startProvisioning();}},_('Re-enter Wi-Fi setup'))
			])
		]);
	},
	startProvisioning:function(){if(!window.confirm(_('The current Wi-Fi management connection may be interrupted. Continue?')))return;fs.exec('/usr/sbin/audiowrtctl',['provisioning','start']).then(function(res){if(res.code)throw new Error(res.stderr||_('Could not start provisioning.'));ui.addNotification(null,E('p',{},_('Provisioning mode started. Connect to the AudioWRT setup network.')));}).catch(function(err){ui.addNotification(null,E('p',{},err.message||String(err)),'error');});},
	handleSaveApply:null,handleSave:null,handleReset:null
});
