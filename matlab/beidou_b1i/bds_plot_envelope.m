function bds_plot_envelope(ax,timeSeconds,low,high,label)
%BDS_PLOT_ENVELOPE Display extrema of every bin, with no raw-data alteration.
% n*sqrt(W) units explicitly avoid a cropped scientific-exponent label.
x=[timeSeconds(:).';timeSeconds(:).';nan(1,numel(timeSeconds))];
y=[low(:).';high(:).';nan(1,numel(timeSeconds))]*1e9;
plot(ax,x(:),y(:),'-','Color',[0 .45 .74]);
grid(ax,'on'); xlabel(ax,'Time from selected start (s)'); ylabel(ax,[label ' (n sqrt(W))']);
end
